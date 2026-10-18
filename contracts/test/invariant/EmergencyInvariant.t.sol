// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {EmergencyHandler} from "./handlers/EmergencyHandler.sol";

/// forge-config: default.invariant.depth = 100
contract EmergencyInvariantTest is Test {
    EmergencyHandler internal handler;

    function setUp() public {
        handler = new EmergencyHandler();

        excludeContract(address(handler.s_usdc()));
        excludeContract(address(handler.s_token()));
        excludeContract(address(handler.s_clock()));
        excludeContract(address(handler.s_pool()));
        excludeContract(address(handler.s_cruiseFarm()));
        excludeContract(address(handler.s_degenFarm()));
        excludeContract(address(handler.s_cruise()));
        excludeContract(address(handler.s_degen()));
        excludeContract(address(handler.s_schedule()));
        excludeContract(address(handler.s_ballot()));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.supply1.selector;
        selectors[1] = handler.supply2.selector;
        selectors[2] = handler.deposit1.selector;
        selectors[3] = handler.harvest.selector;
        selectors[4] = handler.topUp.selector;
        selectors[5] = handler.donate.selector;
        selectors[6] = handler.exit1.selector;
        selectors[7] = handler.exit2.selector;
        selectors[8] = handler.runForcedCases.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_ValuesMatchGhosts() public view {
        assertEq(handler.s_cruise().value(), handler.s_idle1() + handler.s_principal1());
        assertEq(handler.s_degen().value(), handler.s_idle2() + handler.s_principal2());
    }

    function invariant_SumMatchesGhost() public view {
        assertEq(handler.s_cruise().value() + handler.s_degen().value(), handler.s_ghostSum());
    }

    function invariant_DonationStaysOutOfValue() public view {
        assertEq(handler.s_usdc().balanceOf(address(handler.s_cruise())), handler.s_idle1() + handler.s_donated1());
        assertEq(
            handler.s_usdc().balanceOf(address(handler.s_degen())),
            handler.s_idle2() + handler.s_donated2() + handler.s_pending2()
        );
    }

    function afterInvariant() public view {
        assertGt(handler.s_withPrincipal(), 0);
        assertGt(handler.s_emptyActive(), 0);
        assertGt(handler.s_twice(), 0);
        assertGt(handler.s_afterSwitch(), 0);
        assertGt(handler.s_fund1Idle(), 0);
        assertGt(handler.s_harvestAfter(), 0);
        assertGt(handler.s_rebalanceAfter(), 0);
        assertGt(handler.s_topUpAfter(), 0);
        assertGt(handler.s_pausedRejected(), 0);
        assertGt(handler.s_halted(), 0);
        assertGt(handler.s_alreadyPaused(), 0);
        assertGt(handler.s_emptyReason(), 0);
        assertGt(handler.s_unauthorized(), 0);
        assertGt(handler.s_direct(), 0);
        assertGt(handler.s_both(), 0);
        assertGt(handler.s_returnCredits(), 0);
    }
}
