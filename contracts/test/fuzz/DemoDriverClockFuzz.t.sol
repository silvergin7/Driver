// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";

contract DemoDriverClockFuzzTest is Test {
    DemoDriverClock internal clock;
    address internal owner = makeAddr("owner");

    function setUp() public {
        clock = new DemoDriverClock(owner);
    }

    function testFuzz_CurrentTimeIsWarpPlusOffset(uint256 warpBy, uint256 first, uint256 second) public {
        first = bound(first, 1, clock.MAX_ADVANCE());
        second = bound(second, 1, clock.MAX_ADVANCE());
        warpBy = bound(warpBy, 0, 3650 days);

        vm.startPrank(owner);
        clock.advanceTime(first);
        clock.advanceTime(second);
        vm.stopPrank();
        vm.warp(block.timestamp + warpBy);

        assertEq(clock.offset(), first + second);
        assertEq(clock.currentTime(), block.timestamp + first + second);
    }

    function testFuzz_RevertWhen_CallerIsNotOwner(address caller, uint256 secondsForward) public {
        vm.assume(caller != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        clock.advanceTime(secondsForward);

        assertEq(clock.offset(), 0);
    }

    function testFuzz_RevertWhen_AdvanceExceedsMax(uint256 secondsForward) public {
        secondsForward = bound(secondsForward, clock.MAX_ADVANCE() + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                DemoDriverClock.DemoDriverClock__AdvanceTooLarge.selector, secondsForward, clock.MAX_ADVANCE()
            )
        );
        vm.prank(owner);
        clock.advanceTime(secondsForward);

        assertEq(clock.offset(), 0);
    }
}
