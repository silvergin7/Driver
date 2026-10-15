// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";

contract DemoDriverClockTest is Test {
    DemoDriverClock internal clock;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    event TimeAdvanced(uint256 secondsForward, uint256 newOffset);

    function setUp() public {
        clock = new DemoDriverClock(owner);
    }

    function test_ConstructorSetsOwnerAndZeroOffset() public view {
        assertEq(clock.owner(), owner);
        assertEq(clock.offset(), 0);
        assertEq(clock.MAX_ADVANCE(), 365 days);
        assertEq(clock.currentTime(), block.timestamp);
    }

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new DemoDriverClock(address(0));
    }

    function test_AdvanceAddsOffsetAndEmits() public {
        uint256 start = block.timestamp;

        vm.expectEmit(address(clock));
        emit TimeAdvanced(100, 100);

        vm.prank(owner);
        clock.advanceTime(100);

        assertEq(clock.offset(), 100);
        assertEq(clock.currentTime(), start + 100);
    }

    function test_SecondAdvanceEmitsCumulativeOffset() public {
        vm.prank(owner);
        clock.advanceTime(100);

        vm.expectEmit(address(clock));
        emit TimeAdvanced(200, 300);

        vm.prank(owner);
        clock.advanceTime(200);

        assertEq(clock.offset(), 300);
    }

    function test_WarpDoesNotChangeOffset() public {
        vm.prank(owner);
        clock.advanceTime(100);

        vm.warp(block.timestamp + 50);

        assertEq(clock.offset(), 100);
        assertEq(clock.currentTime(), block.timestamp + 100);
    }

    function test_WarpAndAdvanceStack() public {
        vm.warp(block.timestamp + 40);

        vm.prank(owner);
        clock.advanceTime(60);

        assertEq(clock.offset(), 60);
        assertEq(clock.currentTime(), block.timestamp + 60);
    }

    function test_AdvanceOfMaxSucceeds() public {
        uint256 start = block.timestamp;
        uint256 maxAdvance = clock.MAX_ADVANCE();

        vm.expectEmit(address(clock));
        emit TimeAdvanced(maxAdvance, maxAdvance);

        vm.prank(owner);
        clock.advanceTime(maxAdvance);

        assertEq(clock.offset(), maxAdvance);
        assertEq(clock.currentTime(), start + maxAdvance);
    }

    function test_RevertWhen_AdvanceIsOnePastMax() public {
        uint256 timeBefore = clock.currentTime();
        uint256 secondsForward = clock.MAX_ADVANCE() + 1;

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                DemoDriverClock.DemoDriverClock__AdvanceTooLarge.selector, secondsForward, clock.MAX_ADVANCE()
            )
        );
        vm.prank(owner);
        clock.advanceTime(secondsForward);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(clock.offset(), 0);
        assertEq(clock.currentTime(), timeBefore);
    }

    function test_RevertWhen_SecondsAreZero() public {
        vm.expectRevert(DemoDriverClock.DemoDriverClock__ZeroSeconds.selector);
        vm.prank(owner);
        clock.advanceTime(0);

        assertEq(clock.offset(), 0);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        clock.advanceTime(1);

        assertEq(clock.offset(), 0);
    }

    function test_RevertWhen_AdvanceAfterRenounce() public {
        vm.prank(owner);
        clock.advanceTime(1 days);

        address next = makeAddr("next");
        vm.prank(owner);
        clock.transferOwnership(next);
        vm.prank(owner);
        clock.renounceOwnership();

        assertEq(clock.owner(), address(0));
        assertEq(clock.pendingOwner(), address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        clock.advanceTime(1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, next));
        vm.prank(next);
        clock.acceptOwnership();

        assertEq(clock.offset(), 1 days);
        vm.warp(block.timestamp + 10);
        assertEq(clock.currentTime(), block.timestamp + 1 days);
    }

    function test_OwnershipTransfersOnlyAfterAcceptance() public {
        address next = makeAddr("next");

        vm.prank(owner);
        clock.transferOwnership(next);

        assertEq(clock.owner(), owner);
        assertEq(clock.pendingOwner(), next);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, next));
        vm.prank(next);
        clock.advanceTime(1);
        assertEq(clock.offset(), 0);

        vm.prank(next);
        clock.acceptOwnership();

        vm.prank(next);
        clock.advanceTime(1);
        assertEq(clock.offset(), 1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        clock.advanceTime(1);
        assertEq(clock.offset(), 1);
    }
}
