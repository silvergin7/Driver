// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DemoDriverClock} from "../../../src/DemoDriverClock.sol";

contract DriverClockHandler is Test {
    DemoDriverClock internal immutable i_demo;
    address internal immutable i_owner;

    uint256 public s_ghostWarps;
    uint256 public s_ghostAdvances;
    uint256 public s_ghostOffset;
    uint256 public s_recordedDemoTime;
    uint256 public s_previousDemoTime;

    constructor(DemoDriverClock demo, address owner) {
        i_demo = demo;
        i_owner = owner;
        uint256 time = demo.currentTime();
        s_recordedDemoTime = time;
        s_previousDemoTime = time;
    }

    function warpForward(uint256 delta) external {
        delta = bound(delta, 1, 1 days);
        vm.warp(block.timestamp + delta);
        s_ghostWarps += 1;
        _recordDemoTime();
    }

    function advanceDemo(uint256 secondsForward) external {
        secondsForward = bound(secondsForward, 1, i_demo.MAX_ADVANCE());
        vm.prank(i_owner);
        i_demo.advanceTime(secondsForward);
        s_ghostOffset += secondsForward;
        s_ghostAdvances += 1;
        _recordDemoTime();
    }

    function _recordDemoTime() internal {
        uint256 time = i_demo.currentTime();
        s_previousDemoTime = s_recordedDemoTime;
        s_recordedDemoTime = time;
    }
}
