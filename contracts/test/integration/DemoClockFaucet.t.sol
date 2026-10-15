// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverFaucet} from "../../src/DriverFaucet.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DemoClockFaucetTest is Test {
    DriverToken internal token;
    DriverFaucet internal faucet;
    DemoDriverClock internal clock;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        HelperConfig helper = new HelperConfig();
        token = new DriverToken(owner);
        faucet = new DriverFaucet(
            token,
            helper.DVR_FAUCET_CLAIM_AMOUNT(),
            helper.DVR_FAUCET_CLAIM_COOLDOWN(),
            helper.DVR_FAUCET_DAILY_CLAIM_LIMIT()
        );
        clock = new DemoDriverClock(owner);

        vm.startPrank(owner);
        token.mint(owner, helper.FAUCET_ALLOCATION());
        assertTrue(token.transfer(address(faucet), helper.FAUCET_ALLOCATION()));
        vm.stopPrank();
    }

    function test_FaucetCooldownUsesBlockTimestampNotTheDemoClock() public {
        vm.prank(alice);
        faucet.claim();

        uint256 nextClaimAt = faucet.nextClaimAt(alice);
        assertEq(nextClaimAt, block.timestamp + faucet.i_claimCooldown());

        vm.prank(owner);
        clock.advanceTime(2 days);

        assertEq(clock.currentTime(), block.timestamp + 2 days);
        assertGt(clock.currentTime(), nextClaimAt);

        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__ClaimTooSoon.selector, nextClaimAt));
        vm.prank(alice);
        faucet.claim();

        vm.warp(nextClaimAt);
        vm.prank(alice);
        faucet.claim();

        assertEq(token.balanceOf(alice), 2 * faucet.i_claimAmount());
        assertEq(clock.offset(), 2 days);
        assertEq(clock.currentTime(), block.timestamp + 2 days);
    }
}
