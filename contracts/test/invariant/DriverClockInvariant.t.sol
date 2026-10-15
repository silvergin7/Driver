// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverClock} from "../../src/DriverClock.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverClockHandler} from "./handlers/DriverClockHandler.sol";

contract DriverClockInvariantTest is Test {
    DriverClock internal production;
    DemoDriverClock internal demo;
    DriverClockHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        production = new DriverClock();
        demo = new DemoDriverClock(owner);
        handler = new DriverClockHandler(demo, owner);

        excludeContract(address(production));
        excludeContract(address(demo));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.warpForward.selector;
        selectors[1] = handler.advanceDemo.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_DemoOffsetMatchesGhost() public view {
        assertEq(demo.offset(), handler.s_ghostOffset());
    }

    function invariant_DemoTimeIsBlockTimestampPlusGhost() public view {
        assertEq(demo.currentTime(), block.timestamp + handler.s_ghostOffset());
    }

    function invariant_ProductionTimeIsBlockTimestamp() public view {
        assertEq(production.currentTime(), block.timestamp);
    }

    function invariant_DemoTimeNeverDecreases() public view {
        assertGe(demo.currentTime(), handler.s_recordedDemoTime());
        assertGe(handler.s_recordedDemoTime(), handler.s_previousDemoTime());
    }

    function afterInvariant() public view {
        assertGt(handler.s_ghostWarps(), 0);
        assertGt(handler.s_ghostAdvances(), 0);
    }
}
