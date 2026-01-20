// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BaseFountfiTest} from "./BaseFountfiTest.t.sol";
import {GatedMintReportedStrategy} from "../src/strategy/GatedMintRWAStrategy.sol";
import {GatedMintRWA} from "../src/token/GatedMintRWA.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title GatedMintRWAStrategyTest
 * @notice Tests for GatedMintRWAStrategy contract to achieve 100% coverage
 */
contract GatedMintRWAStrategyTest is BaseFountfiTest {
    GatedMintReportedStrategy internal strategy;

    function setUp() public override {
        super.setUp();
    }

    function test_DeployToken() public {
        vm.startPrank(owner);
        strategy = new GatedMintReportedStrategy();

        // Initialize, with arbitrary reporter address
        strategy.initialize("Test Gated RWA", "TGRWA", owner, manager, address(usdc), 6, abi.encode(address(0x123)));
        vm.stopPrank();

        address tokenAddress = strategy.sToken();

        // Verify the token was deployed correctly
        GatedMintRWA token = GatedMintRWA(tokenAddress);
        assertEq(token.name(), "Test Gated RWA");
        assertEq(token.symbol(), "TGRWA");
        assertEq(token.asset(), address(usdc));
        assertEq(token.strategy(), address(strategy));

        // Verify escrow was deployed
        assertTrue(token.escrow() != address(0));
    }
}
