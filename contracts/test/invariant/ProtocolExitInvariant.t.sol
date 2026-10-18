// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MockFarm} from "../../src/MockFarm.sol";
import {ProtocolHandler} from "./handlers/ProtocolHandler.sol";
import {ProtocolInvariantBase} from "./ProtocolInvariant.t.sol";

/// forge-config: default.invariant.depth = 100
contract ProtocolExitInvariantTest is ProtocolInvariantBase {
    function setUp() public {
        _bind(new ProtocolHandler(true));
        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = handler.claimDvr.selector;
        selectors[1] = handler.claimUsdc.selector;
        selectors[2] = handler.buy.selector;
        selectors[3] = handler.sell.selector;
        selectors[4] = handler.harvest1.selector;
        selectors[5] = handler.harvest2.selector;
        selectors[6] = handler.topUp.selector;
        selectors[7] = handler.lock.selector;
        selectors[8] = handler.vote.selector;
        selectors[9] = handler.unlock.selector;
        selectors[10] = handler.skipTime.selector;
        selectors[11] = handler.warp.selector;
        selectors[12] = handler.exit1.selector;
        selectors[13] = handler.exit2.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_ExitedFarmsStayDelisted() public view {
        uint256 count = handler.s_exitedCount();
        for (uint256 i = 0; i < count; i++) {
            address farm = handler.s_exited(i);
            assertFalse(handler.cruiseControl().isStrategy(farm));
            assertFalse(handler.degenDriver().isStrategy(farm));
            assertTrue(MockFarm(farm).paused());
        }
    }

    function afterInvariant() public view override {
        super.afterInvariant();
        if (handler.s_exits()) {
            assertGt(handler.s_exit1(), 0);
            assertGt(handler.s_exit2(), 0);
            assertGt(handler.s_ignored(), 0);
            assertGt(handler.s_harvestAfterExit(), 0);
        }
    }
}
