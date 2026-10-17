// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverClock} from "../../src/DriverClock.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";

contract RoundScheduleTest is Test {
    uint256 internal constant EPOCH = 30 days;

    DemoDriverClock internal clock;
    RoundSchedule internal schedule;
    address internal owner = makeAddr("owner");

    event RoundScheduleStarted(uint256 start, uint256 epoch);

    function setUp() public {
        clock = new DemoDriverClock(owner);
        schedule = new RoundSchedule(clock, EPOCH);
    }

    function test_ConstructorStoresTheClockEpochAndStart() public view {
        assertEq(address(schedule.i_clock()), address(clock));
        assertEq(schedule.i_epoch(), EPOCH);
        assertEq(schedule.i_start(), block.timestamp);
        assertEq(schedule.MIN_EPOCH(), 1 days);
        assertEq(schedule.MAX_EPOCH(), 90 days);
        assertEq(schedule.currentRound(), 0);
        assertEq(schedule.roundStart(0), block.timestamp);
        assertEq(schedule.roundEnd(0), block.timestamp + EPOCH);
    }

    function test_ConstructorEmitsRoundScheduleStarted() public {
        uint256 start = block.timestamp;
        vm.expectEmit(false, false, false, true);
        emit RoundScheduleStarted(start, EPOCH);
        RoundSchedule created = new RoundSchedule(clock, EPOCH);
        assertEq(created.i_start(), start);
        assertEq(created.i_epoch(), EPOCH);
    }

    function test_RevertWhen_ClockIsZeroAddress() public {
        vm.expectRevert(RoundSchedule.RoundSchedule__ZeroAddress.selector);
        new RoundSchedule(IDriverClock(address(0)), EPOCH);
    }

    function test_RevertWhen_EpochIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(RoundSchedule.RoundSchedule__EpochOutOfRange.selector, 0, 1 days, 90 days)
        );
        new RoundSchedule(clock, 0);
    }

    function test_RevertWhen_EpochIsBelowOneDay() public {
        uint256 epoch = 1 days - 1;
        vm.expectRevert(
            abi.encodeWithSelector(RoundSchedule.RoundSchedule__EpochOutOfRange.selector, epoch, 1 days, 90 days)
        );
        new RoundSchedule(clock, epoch);
    }

    function test_ConstructorAcceptsOneDayAndNinetyDays() public {
        RoundSchedule shortest = new RoundSchedule(clock, 1 days);
        RoundSchedule longest = new RoundSchedule(clock, 90 days);
        assertEq(shortest.i_epoch(), 1 days);
        assertEq(longest.i_epoch(), 90 days);
    }

    function test_RevertWhen_EpochIsAboveNinetyDays() public {
        uint256 epoch = 90 days + 1;
        vm.expectRevert(
            abi.encodeWithSelector(RoundSchedule.RoundSchedule__EpochOutOfRange.selector, epoch, 1 days, 90 days)
        );
        new RoundSchedule(clock, epoch);
    }

    function test_RevertWhen_NoRoundHasClosed() public {
        vm.expectRevert(RoundSchedule.RoundSchedule__NoClosedRound.selector);
        schedule.latestClosedRound();
    }

    function test_RoundStaysOpenUntilTheEpoch() public {
        vm.warp(block.timestamp + EPOCH - 1);
        assertEq(schedule.currentRound(), 0);
        vm.expectRevert(RoundSchedule.RoundSchedule__NoClosedRound.selector);
        schedule.latestClosedRound();
    }

    function test_RoundClosesAtTheEpochAndTheNextOpens() public {
        uint256 start = schedule.i_start();
        vm.warp(start + EPOCH);
        assertEq(schedule.currentRound(), 1);
        assertEq(schedule.latestClosedRound(), 0);
        assertEq(schedule.roundEnd(0), schedule.roundStart(1));
        assertEq(schedule.roundEnd(1), start + 2 * EPOCH);
    }

    function test_RoundsChainByTime() public {
        uint256 start = schedule.i_start();
        vm.warp(start + 2 * EPOCH);
        assertEq(schedule.currentRound(), 2);
        assertEq(schedule.latestClosedRound(), 1);
        assertEq(schedule.roundStart(2), start + 2 * EPOCH);
        assertEq(schedule.roundEnd(2), start + 3 * EPOCH);
    }

    function test_DemoAdvanceClosesARound() public {
        vm.prank(owner);
        clock.advanceTime(EPOCH);
        assertEq(schedule.currentRound(), 1);
        assertEq(schedule.latestClosedRound(), 0);
    }

    function test_WarpClosesARoundOnTheProductionClock() public {
        DriverClock production = new DriverClock();
        RoundSchedule productionSchedule = new RoundSchedule(production, EPOCH);
        uint256 start = productionSchedule.i_start();

        vm.warp(start + EPOCH);
        assertEq(productionSchedule.currentRound(), 1);
        assertEq(productionSchedule.latestClosedRound(), 0);

        (bool ok, bytes memory data) = address(production).call(abi.encodeWithSignature("advanceTime(uint256)", EPOCH));
        assertFalse(ok);
        assertEq(data.length, 0);
    }

    function test_HasNoOwnerAndNoEpochSetter() public {
        (bool ownerOk, bytes memory ownerData) = address(schedule).call(abi.encodeWithSignature("owner()"));
        (bool setOk, bytes memory setData) =
            address(schedule).call(abi.encodeWithSignature("setEpoch(uint256)", 1 days));

        assertFalse(ownerOk);
        assertEq(ownerData.length, 0);
        assertFalse(setOk);
        assertEq(setData.length, 0);
        assertEq(schedule.i_epoch(), EPOCH);
    }
}
