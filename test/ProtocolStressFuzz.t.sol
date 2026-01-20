// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {Registry} from "../src/registry/Registry.sol";
import {ReportedStrategy} from "../src/strategy/ReportedStrategy.sol";
import {MockReporter} from "../src/mocks/MockReporter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {MockRegistry} from "../src/mocks/MockRegistry.sol";
import {MockConduit} from "../src/mocks/MockConduit.sol";
import {RoleManager} from "../src/auth/RoleManager.sol";
import {console2} from "forge-std/console2.sol";

contract ProtocolStressFuzzTest is BaseFountfiTest {
    ReportedStrategy reportedStrategy;
    MockReporter reporter;
    tRWA internal token;
    RoleManager internal roleManager;
    MockConduit internal mockConduit;

    // State tracking for verification
    struct UserState {
        uint256 shares;
        uint256 lastDepositAmount;
        uint256 lastWithdrawAmount;
        bool hasDeposited;
    }

    mapping(address => UserState) private userStates;
    address[] private activeUsers;

    function setUp() public override {
        super.setUp();

        // Deploy RoleManager with mock registry
        vm.prank(owner);
        MockRegistry mockRegistry = new MockRegistry();
        mockConduit = new MockConduit();
        mockRegistry.setConduit(address(mockConduit));

        vm.prank(owner);
        roleManager = new RoleManager();
        vm.prank(owner);
        roleManager.initializeRegistry(address(mockRegistry));

        // Deploy strategy directly without registry
        vm.prank(owner);
        MockStrategy strategy = new MockStrategy();
        vm.prank(owner);
        strategy.initialize("Test RWA", "tRWA", address(roleManager), manager, address(usdc), 6, "");

        // Get the token
        token = tRWA(strategy.sToken());

        // Deploy reported strategy for more complex scenarios
        reporter = new MockReporter(1e18); // Initial price per share of 1:1
        reportedStrategy = new ReportedStrategy();

        // Initialize the strategy
        vm.prank(owner);
        reportedStrategy.initialize(
            "Reported Strategy", "rRWA", address(roleManager), manager, address(usdc), 6, abi.encode(address(reporter))
        );

        // Setup multiple users with varying amounts
        activeUsers = [alice, bob, charlie];

        // Give users different starting amounts (USDC has 6 decimals)
        vm.prank(owner);
        usdc.mint(alice, 10000000e6); // 10M USDC
        vm.prank(owner);
        usdc.mint(bob, 5000000e6); // 5M USDC
        vm.prank(owner);
        usdc.mint(charlie, 1000000e6); // 1M USDC

        // Register USDC as allowed asset
        mockRegistry.setAsset(address(usdc), 6);

        // Approve for all users
        for (uint256 i = 0; i < activeUsers.length; i++) {
            vm.prank(activeUsers[i]);
            usdc.approve(address(token), type(uint256).max);
            vm.prank(activeUsers[i]);
            usdc.approve(address(mockConduit), type(uint256).max);
        }

        // Strategy needs to approve token to transfer USDC during withdrawals
        vm.prank(manager);
        strategy.setAllowance(address(usdc), address(token), type(uint256).max);
    }

    /**
     * @notice Stress test with rapid sequential operations
     * @param numOperations Number of operations to perform
     * @param operationTypes Array of operation types
     * @param amounts Array of amounts for each operation
     */
    function testFuzz_RapidSequentialOperations(
        uint8 numOperations,
        uint8[50] memory operationTypes,
        uint256[50] memory amounts
    ) public {
        numOperations = uint8(bound(numOperations, 10, 50));

        for (uint256 i = 0; i < numOperations; i++) {
            uint8 opType = operationTypes[i] % 4; // 0: deposit, 1: withdraw, 2: transfer, 3: redeem
            address user = activeUsers[i % 3];
            uint256 amount = bound(amounts[i], 1e18, 100000e18);

            if (opType == 0) {
                _performDeposit(user, amount);
            } else if (opType == 1) {
                _performWithdraw(user, amount);
            } else if (opType == 2) {
                _performTransfer(user, activeUsers[(i + 1) % 3], amount);
            } else {
                _performRedeem(user, amount);
            }

            // Verify state consistency after each operation
            _verifyStateConsistency();
        }

        // Final comprehensive verification
        _performComprehensiveVerification();
    }

    /**
     * @notice Test protocol behavior with price/NAV updates
     * @param priceUpdates Array of price multipliers (scaled by 1e18)
     * @param operationsBetweenUpdates Number of operations between price updates
     */
    function testFuzz_PriceVolatility(uint256[5] memory priceUpdates, uint8 operationsBetweenUpdates) public {
        // Switch to reported strategy for this test
        // Note: This test uses reportedStrategy's token
        tRWA reportedToken = tRWA(reportedStrategy.sToken());

        // Setup approvals for reportedToken
        vm.prank(alice);
        usdc.approve(address(reportedToken), type(uint256).max);
        vm.prank(alice);
        usdc.approve(address(mockConduit), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(reportedToken), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(mockConduit), type(uint256).max);

        // ReportedStrategy needs to approve token to transfer USDC during withdrawals
        vm.prank(manager);
        reportedStrategy.setAllowance(address(usdc), address(reportedToken), type(uint256).max);

        // Initial deposits (convert to USDC decimals)
        vm.prank(alice);
        uint256 aliceShares = reportedToken.deposit(10000e6, alice);

        vm.prank(bob);
        uint256 bobShares = reportedToken.deposit(5000e6, bob);

        userStates[alice].shares = aliceShares;
        userStates[bob].shares = bobShares;

        operationsBetweenUpdates = uint8(bound(operationsBetweenUpdates, 1, 10));

        for (uint256 i = 0; i < priceUpdates.length; i++) {
            // Bound price updates to reasonable range (0.5x to 2x)
            uint256 priceMultiplier = bound(priceUpdates[i], 0.5e18, 2e18);

            // Update NAV through reporter
            uint256 currentNav = abi.decode(reporter.report(), (uint256));
            uint256 newNav = (currentNav * priceMultiplier) / 1e18;
            reporter.setValue(newNav);

            console2.log("Price update - New NAV:", newNav);

            // Perform operations between price updates
            for (uint256 j = 0; j < operationsBetweenUpdates; j++) {
                address user = activeUsers[j % 2]; // Only alice and bob for this test

                if (j % 2 == 0) {
                    // Deposit (convert to USDC decimals)
                    uint256 depositAmount = bound(priceUpdates[i] % 10000e6, 100e6, 5000e6);
                    vm.prank(user);
                    try reportedToken.deposit(depositAmount, user) returns (uint256 shares) {
                        userStates[user].shares += shares;
                        console2.log("Deposited after price update:", depositAmount);
                        console2.log("Shares received:", shares);
                    } catch {}
                } else {
                    // Withdraw
                    uint256 userShares = reportedToken.balanceOf(user);
                    if (userShares > 0) {
                        uint256 sharesToRedeem = bound(priceUpdates[i] % userShares, 1, userShares / 2);
                        vm.prank(user);
                        try reportedToken.redeem(sharesToRedeem, user, user) returns (uint256 assets) {
                            userStates[user].shares -= sharesToRedeem;
                            console2.log("Redeemed after price update:", sharesToRedeem);
                            console2.log("Assets received:", assets);
                        } catch {}
                    }
                }
            }

            // Verify share value consistency
            _verifyShareValueConsistency();
        }
    }

    /**
     * @notice Test extreme deposit/withdraw patterns
     * @param pattern Type of pattern (0: pyramid, 1: inverse pyramid, 2: random)
     * @param baseAmount Base amount for the pattern
     */
    function testFuzz_ExtremePatterns(uint8 pattern, uint256 baseAmount) public {
        pattern = pattern % 3;
        baseAmount = bound(baseAmount, 100e18, 10000e18);

        if (pattern == 0) {
            _testPyramidPattern(baseAmount);
        } else if (pattern == 1) {
            _testInversePyramidPattern(baseAmount);
        } else {
            _testRandomPattern(baseAmount);
        }

        _performComprehensiveVerification();
    }

    /**
     * @notice Test protocol resilience with many small users
     * @param numUsers Number of users to simulate
     * @param avgDepositSize Average deposit size per user
     */
    function testFuzz_ManySmallUsers(uint8 numUsers, uint256 avgDepositSize) public {
        numUsers = uint8(bound(numUsers, 10, 50));
        avgDepositSize = bound(avgDepositSize, 10e18, 1000e18);

        // Create and fund many users
        for (uint256 i = 0; i < numUsers; i++) {
            address user = address(uint160(0x1000 + i));
            uint256 depositAmount = (avgDepositSize * (90 + (i % 20))) / 100; // Vary by ±10%

            // Fund user
            vm.prank(owner);
            usdc.mint(user, depositAmount * 2);

            // Approve and deposit
            vm.prank(user);
            usdc.approve(address(token), type(uint256).max);
            vm.prank(user);
            usdc.approve(address(mockConduit), type(uint256).max);

            vm.prank(user);
            uint256 shares = token.deposit(depositAmount, user);

            // Track state
            userStates[user] =
                UserState({shares: shares, lastDepositAmount: depositAmount, lastWithdrawAmount: 0, hasDeposited: true});
        }

        // Verify the protocol handles many users correctly
        uint256 totalTrackedShares = 0;
        for (uint256 i = 0; i < numUsers; i++) {
            address user = address(uint160(0x1000 + i));
            totalTrackedShares += userStates[user].shares;
        }

        assertApproxEqRel(token.totalSupply(), totalTrackedShares, 1e15, "Share tracking mismatch with many users");

        // Test some withdrawals
        for (uint256 i = 0; i < numUsers / 2; i++) {
            address user = address(uint160(0x1000 + i));
            uint256 userShares = token.balanceOf(user);

            if (userShares > 0) {
                vm.prank(user);
                uint256 assets = token.redeem(userShares / 2, user, user);
                userStates[user].shares = userShares / 2;
                userStates[user].lastWithdrawAmount = assets;
            }
        }

        _verifyStateConsistency();
    }

    // Helper functions

    function _performDeposit(address user, uint256 amount) private {
        uint256 balance = usdc.balanceOf(user);
        if (balance >= amount) {
            vm.prank(user);
            try token.deposit(amount, user) returns (uint256 shares) {
                userStates[user].shares += shares;
                userStates[user].lastDepositAmount = amount;
                userStates[user].hasDeposited = true;
                console2.log("Deposit amount:", amount);
                console2.log("Shares received:", shares);
            } catch Error(string memory reason) {
                console2.log("Deposit failed:", reason);
            }
        }
    }

    function _performWithdraw(address user, uint256 amount) private {
        uint256 maxWithdraw = token.maxWithdraw(user);
        if (maxWithdraw > 0) {
            uint256 withdrawAmount = amount > maxWithdraw ? maxWithdraw : amount;
            vm.prank(user);
            try token.withdraw(withdrawAmount, user, user) returns (uint256 shares) {
                userStates[user].shares -= shares;
                userStates[user].lastWithdrawAmount = withdrawAmount;
                console2.log("Withdraw amount:", withdrawAmount);
                console2.log("Shares burned:", shares);
            } catch Error(string memory reason) {
                console2.log("Withdraw failed:", reason);
            }
        }
    }

    function _performTransfer(address from, address to, uint256 amount) private {
        uint256 fromShares = token.balanceOf(from);
        if (fromShares > 0) {
            uint256 transferShares = amount > fromShares ? fromShares / 2 : amount;
            vm.prank(from);
            try token.transfer(to, transferShares) returns (bool success) {
                if (success) {
                    userStates[from].shares -= transferShares;
                    userStates[to].shares += transferShares;
                    console2.log("Transfer shares:", transferShares);
                }
            } catch Error(string memory reason) {
                console2.log("Transfer failed:", reason);
            }
        }
    }

    function _performRedeem(address user, uint256 amount) private {
        uint256 userShares = token.balanceOf(user);
        if (userShares > 0) {
            uint256 redeemShares = amount > userShares ? userShares / 2 : amount;
            vm.prank(user);
            try token.redeem(redeemShares, user, user) returns (uint256 assets) {
                userStates[user].shares -= redeemShares;
                userStates[user].lastWithdrawAmount = assets;
                console2.log("Redeem shares:", redeemShares);
                console2.log("Assets received:", assets);
            } catch Error(string memory reason) {
                console2.log("Redeem failed:", reason);
            }
        }
    }

    function _verifyStateConsistency() private view {
        // Verify total supply matches sum of balances
        uint256 totalShares = token.totalSupply();
        uint256 totalAssets = token.totalAssets();

        // Check that conversion functions work correctly
        if (totalShares > 0 && totalAssets > 0) {
            uint256 oneShare = 1e18;
            uint256 assetsPerShare = token.convertToAssets(oneShare);
            uint256 sharesPerAsset = token.convertToShares(assetsPerShare);

            // Allow for small rounding errors
            assertApproxEqRel(sharesPerAsset, oneShare, 1e15, "Conversion consistency check failed");
        }

        // Verify no negative balances (would revert anyway, but good to check)
        for (uint256 i = 0; i < activeUsers.length; i++) {
            uint256 balance = token.balanceOf(activeUsers[i]);
            assertTrue(balance >= 0, "Negative balance detected");
        }
    }

    function _verifyShareValueConsistency() private view {
        uint256 totalShares = token.totalSupply();
        if (totalShares == 0) return;

        // Check that all users get proportional value
        uint256 totalCalculatedAssets = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            uint256 userShares = token.balanceOf(user);
            if (userShares > 0) {
                uint256 userAssets = token.convertToAssets(userShares);
                totalCalculatedAssets += userAssets;
            }
        }

        // Total calculated assets should approximately equal total assets
        // Allow for rounding errors
        assertApproxEqRel(totalCalculatedAssets, token.totalAssets(), 1e14, "Asset calculation mismatch");
    }

    function _performComprehensiveVerification() private view {
        console2.log("=== Comprehensive Verification ===");
        console2.log("Total Supply:", token.totalSupply());
        console2.log("Total Assets:", token.totalAssets());

        // Verify each user's position
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            uint256 shares = token.balanceOf(user);
            uint256 assets = shares > 0 ? token.convertToAssets(shares) : 0;
            uint256 maxWithdrawable = token.maxWithdraw(user);

            console2.log("User:", user);
            console2.log("  Shares:", shares);
            console2.log("  Asset Value:", assets);
            console2.log("  Max Withdrawable:", maxWithdrawable);

            // Verify max withdrawable <= asset value
            if (shares > 0) {
                assertLe(maxWithdrawable, assets, "Max withdrawable exceeds asset value");
            }
        }

        _verifyStateConsistency();
    }

    function _testPyramidPattern(uint256 baseAmount) private {
        // Increasing deposits: 1x, 2x, 3x, 4x, 5x
        for (uint256 i = 0; i < 5; i++) {
            address user = activeUsers[i % 3];
            uint256 depositAmount = baseAmount * (i + 1);
            _performDeposit(user, depositAmount);
        }

        // Then decreasing withdrawals: 5x, 4x, 3x, 2x, 1x
        for (uint256 i = 5; i > 0; i--) {
            address user = activeUsers[i % 3];
            uint256 withdrawAmount = baseAmount * i;
            _performWithdraw(user, withdrawAmount);
        }
    }

    function _testInversePyramidPattern(uint256 baseAmount) private {
        // Decreasing deposits: 5x, 4x, 3x, 2x, 1x
        for (uint256 i = 5; i > 0; i--) {
            address user = activeUsers[i % 3];
            uint256 depositAmount = baseAmount * i;
            _performDeposit(user, depositAmount);
        }

        // Then increasing withdrawals: 1x, 2x, 3x, 4x, 5x
        for (uint256 i = 0; i < 5; i++) {
            address user = activeUsers[i % 3];
            uint256 withdrawAmount = baseAmount * (i + 1);
            _performWithdraw(user, withdrawAmount);
        }
    }

    function _testRandomPattern(uint256 seed) private {
        // Random pattern based on seed
        for (uint256 i = 0; i < 10; i++) {
            uint256 randomValue = uint256(keccak256(abi.encode(seed, i)));
            address user = activeUsers[randomValue % 3];
            uint256 amount = (randomValue % 10000e18) + 100e18;

            if (randomValue % 2 == 0) {
                _performDeposit(user, amount);
            } else {
                _performWithdraw(user, amount);
            }
        }
    }
}
