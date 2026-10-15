// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverClock} from "../../src/DriverClock.sol";

contract DriverClockTest is Test {
    DriverClock internal clock;

    function setUp() public {
        clock = new DriverClock();
    }

    function test_CurrentTimeEqualsBlockTimestamp() public view {
        assertEq(clock.currentTime(), block.timestamp);
    }

    function test_CurrentTimeFollowsWarp() public {
        vm.warp(1_000);
        assertEq(clock.currentTime(), 1_000);

        vm.warp(500);
        assertEq(clock.currentTime(), 500);
    }

    function test_RevertWhen_AdvanceTimeIsCalled() public {
        uint256 timeBefore = clock.currentTime();

        (bool ok, bytes memory data) = address(clock).call(abi.encodeWithSignature("advanceTime(uint256)", 1));

        assertFalse(ok);
        assertEq(data.length, 0);
        assertEq(clock.currentTime(), timeBefore);
    }

    function test_HasNoOwner() public {
        (bool ok, bytes memory data) = address(clock).call(abi.encodeWithSignature("owner()"));

        assertFalse(ok);
        assertEq(data.length, 0);
    }
}
