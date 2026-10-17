// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {RebalanceHandler} from "./handlers/RebalanceHandler.sol";

/// forge-config: default.invariant.depth = 100
contract RebalanceInvariantTest is Test {
    RebalanceHandler internal handler;

    function setUp() public {
        handler = new RebalanceHandler();

        excludeContract(address(handler.s_usdc()));
        excludeContract(address(handler.s_token()));
        excludeContract(address(handler.s_clock()));
        excludeContract(address(handler.s_pool()));
        excludeContract(address(handler.s_farm()));
        excludeContract(address(handler.s_cruise()));
        excludeContract(address(handler.s_degen()));
        excludeContract(address(handler.s_schedule()));
        excludeContract(address(handler.s_ballot()));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.supply1.selector;
        selectors[1] = handler.supply2.selector;
        selectors[2] = handler.harvest.selector;
        selectors[3] = handler.topUp.selector;
        selectors[4] = handler.donate.selector;
        selectors[5] = handler.park.selector;
        selectors[6] = handler.setFarm2.selector;
        selectors[7] = handler.runForcedCases.selector;
        selectors[8] = handler.topUpOnFarm.selector;
        selectors[9] = handler.harvestFromFarm.selector;
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
        assertGt(handler.s_below(), 0);
        assertGt(handler.s_at(), 0);
        assertGt(handler.s_above(), 0);
        assertGt(handler.s_rounding(), 0);
        assertGt(handler.s_doubleMove(), 0);
        assertGt(handler.s_doubleTop(), 0);
        assertGt(handler.s_capRevert(), 0);
        assertGt(handler.s_zeroAmount(), 0);
        assertGt(handler.s_emptyReason(), 0);
        assertGt(handler.s_unauthorized(), 0);
        assertGt(handler.s_noFarm(), 0);
        assertGt(handler.s_idleThenFarm(), 0);
        assertGt(handler.s_fund1Holds(), 0);
        assertGt(handler.s_donation(), 0);
        assertGt(handler.s_rewarded(), 0);
        assertGt(handler.s_fromFarm(), 0);
        assertGt(handler.s_rewardedMove(), 0);
        assertGt(handler.s_topUpOnFarm(), 0);
    }
}
