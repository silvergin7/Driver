// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverClock} from "../../src/DriverClock.sol";

contract DriverClockFuzzTest is Test {
    DriverClock internal clock;

    function setUp() public {
        clock = new DriverClock();
    }

    function testFuzz_CurrentTimeTracksWarp(uint256 timestamp) public {
        timestamp = bound(timestamp, 0, type(uint64).max);

        vm.warp(timestamp);

        assertEq(clock.currentTime(), timestamp);
    }
}
