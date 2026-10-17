// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {HarvestHandler} from "./handlers/HarvestHandler.sol";

/// forge-config: default.invariant.depth = 200
contract HarvestInvariantTest is Test {
    HarvestHandler internal handler;

    function setUp() public {
        handler = new HarvestHandler();

        excludeContract(address(handler.s_usdc()));
        excludeContract(address(handler.s_token()));
        excludeContract(address(handler.s_clock()));
        excludeContract(address(handler.s_pool()));
        excludeContract(address(handler.s_fund()));
        excludeContract(address(handler.s_openFund()));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = handler.harvestAcrossClosedRounds.selector;
        selectors[1] = handler.harvestByWarp.selector;
        selectors[2] = handler.harvestAgain.selector;
        selectors[3] = handler.harvestZeroRewards.selector;
        selectors[4] = handler.harvestDust.selector;
        selectors[5] = handler.harvestSlippage.selector;
        selectors[6] = handler.harvestWithNoFarm.selector;
        selectors[7] = handler.harvestWithWinner.selector;
        selectors[8] = handler.refillReserve.selector;
        selectors[9] = handler.unauthorizedHarvest.selector;
        selectors[10] = handler.donateUsdc.selector;
        selectors[11] = handler.donateDvr.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_BoughtBackMatchesGhost() public view {
        assertEq(handler.s_fund().dvrBoughtBack(), handler.s_ghostBought());
    }

    function invariant_MintedMatchesGhost() public view {
        assertEq(handler.s_token().totalMinted(), handler.s_ghostMinted());
    }

    function invariant_BalanceMatchesGhost() public view {
        assertEq(
            handler.s_usdc().balanceOf(address(handler.s_fund())),
            handler.s_ghostIdle() + handler.s_ghostHeld() + handler.s_ghostPending() + handler.s_ghostDonatedUsdc()
        );
    }

    function invariant_ValueMatchesIdlePlusPrincipal() public view {
        assertEq(handler.s_fund().value(), handler.s_ghostIdle() + handler.s_ghostPrincipal());
    }

    function invariant_ProductDoesNotDecrease() public view {
        assertGe(handler.s_kAfter(), handler.s_kBefore());
    }

    function invariant_LastRoundMatchesGhost() public view {
        if (handler.s_roundKnown()) {
            (bool harvested, uint256 roundId) = handler.s_fund().lastHarvestedRound();
            assertTrue(harvested);
            assertEq(roundId, handler.s_lastRound());
        }
    }

    function invariant_DonatedDvrStays() public view {
        assertEq(handler.s_token().balanceOf(address(handler.s_fund())), handler.s_ghostDonatedDvr());
    }

    function invariant_ReservesMatchGhost() public view {
        assertEq(handler.s_pool().reserveDvr(), handler.s_reserveDvr());
        assertEq(handler.s_pool().reserveUsdc(), handler.s_reserveUsdc());
    }

    function afterInvariant() public view {
        assertGt(handler.s_across(), 0);
        assertGt(handler.s_warps(), 0);
        assertGt(handler.s_again(), 0);
        assertGt(handler.s_zeroRewards(), 0);
        assertGt(handler.s_dust(), 0);
        assertGt(handler.s_slippage(), 0);
        assertGt(handler.s_noFarm(), 0);
        assertGt(handler.s_winners(), 0);
        assertGt(handler.s_zeroWinners(), 0);
        assertGt(handler.s_refills(), 0);
        assertGt(handler.s_unauthorized(), 0);
        assertGt(handler.s_usdcDonations(), 0);
        assertGt(handler.s_dvrDonations(), 0);
        assertGt(handler.s_fullPays(), 0);
        assertGt(handler.s_cappedPays(), 0);
    }
}
