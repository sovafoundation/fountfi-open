// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {ManagedWithdrawReportedStrategy} from "../src/strategy/ManagedWithdrawRWAStrategy.sol";
import {ManagedWithdrawRWA} from "../src/token/ManagedWithdrawRWA.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockReporter} from "../src/mocks/MockReporter.sol";
import {MockRegistry} from "../src/mocks/MockRegistry.sol";
import {MockConduit} from "../src/mocks/MockConduit.sol";
import {MockRoleManager} from "../src/mocks/MockRoleManager.sol";
import {tRWA} from "../src/token/tRWA.sol";
import {IStrategy} from "../src/strategy/IStrategy.sol";

/**
 * @title TestManagedWithdrawReportedStrategy
 * @notice Test contract to expose internal functions and add test helpers
 */
contract TestManagedWithdrawReportedStrategy is ManagedWithdrawReportedStrategy {
    function deployTokenPublic(string calldata name_, string calldata symbol_, address asset_, uint8 assetDecimals_)
        external
        returns (address)
    {
        return _deployToken(name_, symbol_, asset_, assetDecimals_);
    }

    function setTokenPublic(address token_) external {
        sToken = token_;
    }

    function setNonceUsed(address user, uint96 nonce) external {
        usedNonces[user][nonce] = true;
    }

    function usedNoncesPublic(address user, uint96 nonce) external view returns (bool) {
        return usedNonces[user][nonce];
    }

    // Debug function to check manager directly
    function isManager(address addr) external view returns (bool) {
        return addr == manager;
    }
}

/**
 * @title ManagedWithdrawReportedStrategyTest
 * @notice Tests for ManagedWithdrawReportedStrategy contract to achieve 100% coverage
 */
contract ManagedWithdrawReportedStrategyTest is BaseFountfiTest {
    TestManagedWithdrawReportedStrategy internal strategy;
    ManagedWithdrawRWA internal token;
    MockRegistry internal mockRegistry;
    MockConduit internal mockConduit;
    MockRoleManager internal mockRoleManager;

    // Test data for EIP-712 signatures
    uint256 internal constant USER_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal user;

    // EIP-712 domain separator
    bytes32 internal DOMAIN_SEPARATOR;
    bytes32 internal constant WITHDRAWAL_REQUEST_TYPEHASH = keccak256(
        "WithdrawalRequest(address owner,address to,uint256 shares,uint256 minAssets,uint96 nonce,uint96 expirationTime)"
    );

    function setUp() public override {
        super.setUp();

        user = vm.addr(USER_PRIVATE_KEY);

        // Deploy mocks
        mockRoleManager = new MockRoleManager(owner);
        mockRegistry = new MockRegistry();
        mockConduit = new MockConduit();

        // Set up registry
        mockRegistry.setConduit(address(mockConduit));

        // Grant manager the STRATEGY_MANAGER role
        mockRoleManager.grantRole(manager, mockRoleManager.STRATEGY_MANAGER());

        vm.prank(owner);
        strategy = new TestManagedWithdrawReportedStrategy();

        // Initialize strategy
        bytes memory initData = abi.encode(address(mockReporter));
        strategy.initialize(
            "Managed RWA",
            "MRWA",
            address(mockRoleManager), // Fixed: was passing owner instead of roleManager
            manager,
            address(usdc),
            6,
            initData
        );

        // Deploy token
        address tokenAddress = strategy.deployTokenPublic("Test Token", "TT", address(usdc), 6);
        token = ManagedWithdrawRWA(tokenAddress);

        // Set up token in strategy
        strategy.setTokenPublic(address(token));

        // Calculate domain separator (must match the one in strategy)
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ManagedWithdrawReportedStrategy")),
                keccak256(bytes("V1")), // Fixed: Should be "V1" not "1"
                block.chainid,
                address(strategy)
            )
        );

        // Fund strategy with USDC for redemptions (strategy needs funds to transfer to token)
        deal(address(usdc), address(strategy), 1000000 * 10 ** 6);

        // Give user some shares
        deal(address(token), user, 10000 * 10 ** 18);

        // Approve strategy to spend USDC (for _collect function in token)
        vm.prank(address(strategy));
        usdc.approve(address(token), type(uint256).max);
    }

    function test_Initialize() public {
        TestManagedWithdrawReportedStrategy newStrategy = new TestManagedWithdrawReportedStrategy();
        bytes memory initData = abi.encode(address(mockReporter));

        newStrategy.initialize("Managed RWA", "MRWA", address(mockRoleManager), manager, address(usdc), 6, initData);

        assertEq(newStrategy.manager(), manager);
        assertEq(newStrategy.asset(), address(usdc));
    }

    function test_DeployToken() public {
        TestManagedWithdrawReportedStrategy newStrategy = new TestManagedWithdrawReportedStrategy();
        bytes memory initData = abi.encode(address(mockReporter));
        newStrategy.initialize("Test", "TST", address(mockRoleManager), manager, address(usdc), 6, initData);

        address tokenAddress = newStrategy.deployTokenPublic("Test Managed RWA", "TMRWA", address(usdc), 6);

        // Verify the token was deployed correctly
        ManagedWithdrawRWA deployedToken = ManagedWithdrawRWA(tokenAddress);
        assertEq(deployedToken.name(), "Test Managed RWA");
        assertEq(deployedToken.symbol(), "TMRWA");
        assertEq(deployedToken.asset(), address(usdc));
        assertEq(deployedToken.strategy(), address(newStrategy));
    }

    function test_RedeemWithValidSignature() public {
        // Debug: Verify manager is set correctly
        assertEq(strategy.manager(), manager, "Manager not set correctly");

        // Debug: Check user address
        assertEq(user, vm.addr(USER_PRIVATE_KEY), "User address mismatch");

        // Create a withdrawal request
        ManagedWithdrawReportedStrategy.WithdrawalRequest memory request = ManagedWithdrawReportedStrategy
            .WithdrawalRequest({
            shares: 1000 * 10 ** 18,
            minAssets: 900 * 10 ** 6,
            owner: user,
            nonce: 1,
            to: user,
            expirationTime: uint96(block.timestamp + 1 hours)
        });

        // Generate EIP-712 signature
        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAWAL_REQUEST_TYPEHASH,
                request.owner,
                request.to,
                request.shares,
                request.minAssets,
                request.nonce,
                request.expirationTime
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        ManagedWithdrawReportedStrategy.Signature memory signature =
            ManagedWithdrawReportedStrategy.Signature({v: v, r: r, s: s});

        // User needs to approve strategy to spend their shares
        vm.prank(user);
        token.approve(address(strategy), request.shares);

        // Execute redeem as manager
        uint256 userBalanceBefore = usdc.balanceOf(user);

        vm.prank(manager);
        strategy.redeem(request, signature);

        uint256 userBalanceAfter = usdc.balanceOf(user);

        // Verify user received USDC
        assertGt(userBalanceAfter, userBalanceBefore);

        // Verify nonce is marked as used
        assertTrue(strategy.usedNoncesPublic(user, 1));
    }

    function test_BatchRedeemWithValidSignatures() public {
        // Verify manager is set properly
        assertEq(strategy.manager(), manager, "Manager not set correctly");

        // Create multiple withdrawal requests
        ManagedWithdrawReportedStrategy.WithdrawalRequest[] memory requests =
            new ManagedWithdrawReportedStrategy.WithdrawalRequest[](2);
        ManagedWithdrawReportedStrategy.Signature[] memory signatures =
            new ManagedWithdrawReportedStrategy.Signature[](2);

        // First request - ensure amounts are reasonable
        requests[0] = ManagedWithdrawReportedStrategy.WithdrawalRequest({
            shares: 500 * 10 ** 18,
            minAssets: 400 * 10 ** 6, // Reduced min to ensure it passes
            owner: user,
            nonce: 1,
            to: user,
            expirationTime: uint96(block.timestamp + 1 hours)
        });

        // Second request
        requests[1] = ManagedWithdrawReportedStrategy.WithdrawalRequest({
            shares: 300 * 10 ** 18,
            minAssets: 200 * 10 ** 6, // Reduced min to ensure it passes
            owner: user,
            nonce: 2,
            to: user,
            expirationTime: uint96(block.timestamp + 1 hours)
        });

        // Generate signatures for both requests
        for (uint256 i = 0; i < 2; i++) {
            bytes32 structHash = keccak256(
                abi.encode(
                    WITHDRAWAL_REQUEST_TYPEHASH,
                    requests[i].owner,
                    requests[i].to,
                    requests[i].shares,
                    requests[i].minAssets,
                    requests[i].nonce,
                    requests[i].expirationTime
                )
            );

            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

            signatures[i] = ManagedWithdrawReportedStrategy.Signature({v: v, r: r, s: s});
        }

        // User needs to approve strategy to spend their shares
        vm.prank(user);
        token.approve(address(strategy), requests[0].shares + requests[1].shares);

        // Execute batch redeem as manager
        uint256 userBalanceBefore = usdc.balanceOf(user);

        // Use low-level call to ensure we're calling the right function
        vm.prank(manager);
        (bool success,) = address(strategy).call(
            abi.encodeWithSelector(ManagedWithdrawReportedStrategy.batchRedeem.selector, requests, signatures)
        );
        require(success, "Batch redeem call failed");

        uint256 userBalanceAfter = usdc.balanceOf(user);

        // Verify user received USDC
        assertGt(userBalanceAfter, userBalanceBefore);

        // Verify both nonces are marked as used
        assertTrue(strategy.usedNoncesPublic(user, 1));
        assertTrue(strategy.usedNoncesPublic(user, 2));
    }

    function test_BatchRedeemWithInvalidArrayLengths() public {
        ManagedWithdrawReportedStrategy.WithdrawalRequest[] memory requests =
            new ManagedWithdrawReportedStrategy.WithdrawalRequest[](2);
        ManagedWithdrawReportedStrategy.Signature[] memory signatures =
            new ManagedWithdrawReportedStrategy.Signature[](1); // Different length

        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawReportedStrategy.InvalidArrayLengths.selector);
        strategy.batchRedeem(requests, signatures);
    }

    function test_RedeemUnauthorized() public {
        ManagedWithdrawReportedStrategy.WithdrawalRequest memory request = ManagedWithdrawReportedStrategy
            .WithdrawalRequest({
            shares: 1000,
            minAssets: 900,
            owner: user,
            nonce: 1,
            to: user,
            expirationTime: uint96(block.timestamp + 1 hours)
        });

        ManagedWithdrawReportedStrategy.Signature memory signature =
            ManagedWithdrawReportedStrategy.Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))});

        vm.prank(alice); // Not manager
        vm.expectRevert(abi.encodeWithSelector(IStrategy.Unauthorized.selector));
        strategy.redeem(request, signature);
    }

    function test_ValidateRedeemExpired() public {
        ManagedWithdrawReportedStrategy.WithdrawalRequest memory request = ManagedWithdrawReportedStrategy
            .WithdrawalRequest({
            shares: 1000,
            minAssets: 900,
            owner: user,
            nonce: 1,
            to: user,
            expirationTime: uint96(block.timestamp - 1) // Expired
        });

        ManagedWithdrawReportedStrategy.Signature memory signature =
            ManagedWithdrawReportedStrategy.Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))});

        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawReportedStrategy.WithdrawalRequestExpired.selector);
        strategy.redeem(request, signature);
    }

    function test_ValidateRedeemNonceReuse() public {
        // Create a valid withdrawal request
        ManagedWithdrawReportedStrategy.WithdrawalRequest memory request = ManagedWithdrawReportedStrategy
            .WithdrawalRequest({
            shares: 1000 * 10 ** 18,
            minAssets: 900 * 10 ** 6,
            owner: user,
            nonce: 1,
            to: user,
            expirationTime: uint96(block.timestamp + 1 hours)
        });

        // Generate valid signature
        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAWAL_REQUEST_TYPEHASH,
                request.owner,
                request.to,
                request.shares,
                request.minAssets,
                request.nonce,
                request.expirationTime
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        ManagedWithdrawReportedStrategy.Signature memory signature =
            ManagedWithdrawReportedStrategy.Signature({v: v, r: r, s: s});

        // User needs to approve strategy to spend their shares
        vm.prank(user);
        token.approve(address(strategy), request.shares * 2); // Approve for both attempts

        // First redeem should succeed
        vm.prank(manager);
        strategy.redeem(request, signature);

        // Second redeem with same nonce should fail
        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawReportedStrategy.WithdrawNonceReuse.selector);
        strategy.redeem(request, signature);
    }

    function test_VerifySignatureInvalid() public {
        // Create a withdrawal request
        ManagedWithdrawReportedStrategy.WithdrawalRequest memory request = ManagedWithdrawReportedStrategy
            .WithdrawalRequest({
            shares: 1000 * 10 ** 18,
            minAssets: 900 * 10 ** 6,
            owner: user,
            nonce: 1,
            to: user,
            expirationTime: uint96(block.timestamp + 1 hours)
        });

        // Create invalid signature (signed by different key)
        uint256 wrongPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        bytes32 structHash = keccak256(
            abi.encode(
                WITHDRAWAL_REQUEST_TYPEHASH,
                request.owner,
                request.to,
                request.shares,
                request.minAssets,
                request.nonce,
                request.expirationTime
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        ManagedWithdrawReportedStrategy.Signature memory signature =
            ManagedWithdrawReportedStrategy.Signature({v: v, r: r, s: s});

        // Execute redeem as manager - should fail due to invalid signature
        vm.prank(manager);
        vm.expectRevert(ManagedWithdrawReportedStrategy.WithdrawInvalidSignature.selector);
        strategy.redeem(request, signature);
    }
}
