// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {ProtocolHandler} from "./handlers/ProtocolHandler.sol";

abstract contract ProtocolInvariantBase is Test {
    ProtocolHandler internal handler;

    function _bind(ProtocolHandler created) internal {
        handler = created;
        assertEq(handler.s_dvrClaims(), 0);
        assertEq(handler.s_usdcClaims(), 0);
        assertEq(handler.s_buys(), 0);
        assertEq(handler.s_sells(), 0);
        assertEq(handler.s_revoted(), 0);
        assertEq(handler.s_buyback(), 0);
        assertEq(handler.s_capped(), 0);
        assertEq(handler.s_switched(), 0);
        assertEq(handler.s_rebalance(), 0);
        assertEq(handler.s_topUp(), 0);
        assertEq(handler.s_tieKept(), 0);
        assertEq(handler.s_unlockAfterVote(), 0);
        assertEq(handler.s_exit1(), 0);
        assertEq(handler.s_exit2(), 0);
        assertEq(handler.s_ignored(), 0);
        assertEq(handler.s_harvestAfterExit(), 0);
        assertEq(handler.s_exitedCount(), 0);

        excludeContract(address(handler.token()));
        excludeContract(address(handler.dvrFaucet()));
        excludeContract(address(handler.usdc()));
        excludeContract(address(handler.usdcFaucet()));
        excludeContract(address(handler.clock()));
        excludeContract(address(handler.splitter()));
        excludeContract(address(handler.pool()));
        excludeContract(address(handler.cruise()));
        excludeContract(address(handler.highway()));
        excludeContract(address(handler.autobahn()));
        excludeContract(address(handler.drift()));
        excludeContract(address(handler.schedule()));
        excludeContract(address(handler.cruiseControl()));
        excludeContract(address(handler.degenDriver()));
        excludeContract(address(handler.driverVote()));
        excludeContract(handler.script());
        targetContract(address(handler));
    }

    function invariant_TotalMintedStaysAtTheCap() public view {
        DriverToken token = handler.token();
        assertEq(token.totalMinted(), token.MAX_SUPPLY());
        assertLe(token.totalMinted(), token.MAX_SUPPLY());
    }

    function invariant_SupplyMatchesMintedMinusGhostBurned() public view {
        DriverToken token = handler.token();
        assertLe(token.totalSupply(), token.totalMinted());
        assertEq(token.totalSupply(), token.totalMinted() - handler.s_ghostBurned());
    }

    function invariant_SystemBalancesMatchGhosts() public view {
        assertEq(_usdcSum(), handler.s_ghostUsdc());
        assertEq(_dvrSum(), handler.s_ghostDvr());
    }

    function invariant_BalancesMatchAddressGhosts() public view {
        MockUSDC usdc = handler.usdc();
        DriverToken token = handler.token();
        assertEq(
            usdc.balanceOf(address(handler.cruiseControl())),
            handler.s_idle1() + handler.s_held1() + handler.s_pending1()
        );
        assertEq(
            usdc.balanceOf(address(handler.degenDriver())), handler.s_idle2() + handler.s_held2() + handler.s_pending2()
        );
        assertEq(token.balanceOf(address(handler.cruiseControl())), 0);
        assertEq(token.balanceOf(address(handler.degenDriver())), 0);
        assertEq(usdc.balanceOf(address(handler.cruise())), handler.s_principal(0) + handler.s_farmReserve(0));
        assertEq(usdc.balanceOf(address(handler.highway())), handler.s_principal(1) + handler.s_farmReserve(1));
        assertEq(usdc.balanceOf(address(handler.autobahn())), handler.s_principal(2) + handler.s_farmReserve(2));
        assertEq(usdc.balanceOf(address(handler.drift())), handler.s_principal(3) + handler.s_farmReserve(3));
        assertEq(token.balanceOf(address(handler.cruise())), 0);
        assertEq(token.balanceOf(address(handler.highway())), 0);
        assertEq(token.balanceOf(address(handler.autobahn())), 0);
        assertEq(token.balanceOf(address(handler.drift())), 0);
        assertEq(usdc.balanceOf(address(handler.splitter())), handler.s_tax1() + handler.s_tax2() + handler.s_tax3());
        assertEq(token.balanceOf(address(handler.splitter())), 0);
        assertEq(usdc.balanceOf(address(handler.pool())), handler.s_reserveUsdc());
        assertEq(token.balanceOf(address(handler.pool())), handler.s_reserveDvr());
        assertEq(token.balanceOf(address(handler.dvrFaucet())), handler.i_faucetStart() - handler.s_dvrPaid());
        assertEq(usdc.balanceOf(address(handler.dvrFaucet())), 0);
        assertEq(usdc.balanceOf(address(handler.usdcFaucet())), 0);
        assertEq(token.balanceOf(address(handler.usdcFaucet())), 0);
        assertEq(token.balanceOf(address(handler.driverVote())), handler.lockSum());
        assertEq(usdc.balanceOf(address(handler.driverVote())), 0);
        assertEq(handler.splitter().accrued(TaxSplitter.FundId.Fund1), handler.s_tax1());
        assertEq(handler.splitter().accrued(TaxSplitter.FundId.Fund2), handler.s_tax2());
        assertEq(handler.splitter().accrued(TaxSplitter.FundId.Fund3), handler.s_tax3());
    }

    function invariant_FundValuesMatchGhosts() public view {
        assertEq(handler.cruiseControl().value(), handler.s_value1());
        assertEq(handler.degenDriver().value(), handler.s_value2());
    }

    function invariant_KMatchesGhostReserves() public view {
        uint256 reserveDvr = handler.pool().reserveDvr();
        uint256 reserveUsdc = handler.pool().reserveUsdc();
        assertEq(reserveDvr, handler.s_reserveDvr());
        assertEq(reserveUsdc, handler.s_reserveUsdc());
        assertGe(reserveDvr * reserveUsdc, handler.s_ghostK());
    }

    function invariant_CountedMatchesLocks() public view {
        assertEq(handler.driverVote().counted(), handler.lockSum());
        assertEq(handler.token().balanceOf(address(handler.driverVote())), handler.lockSum());
    }

    function invariant_ActiveFarmsAreNotPaused() public view {
        MockFarm active1 = MockFarm(address(handler.cruiseControl().activeFarm()));
        if (address(active1) != address(0)) {
            assertFalse(active1.paused());
        }
        MockFarm active2 = MockFarm(address(handler.degenDriver().activeFarm()));
        if (address(active2) != address(0)) {
            assertFalse(active2.paused());
        }
    }

    function invariant_ClockMatchesGhostTime() public view {
        assertEq(handler.clock().currentTime(), block.timestamp + handler.s_ghostOffset());
    }

    function afterInvariant() public view virtual {
        assertGt(handler.s_dvrClaims(), 0);
        assertGt(handler.s_usdcClaims(), 0);
        assertGt(handler.s_buys(), 0);
        assertGt(handler.s_sells(), 0);
        assertGt(handler.s_revoted(), 0);
        assertGt(handler.s_buyback(), 0);
        assertGt(handler.s_capped(), 0);
        assertGt(handler.s_switched(), 0);
        assertGt(handler.s_rebalance(), 0);
        assertGt(handler.s_topUp(), 0);
        assertGt(handler.s_tieKept(), 0);
        assertGt(handler.s_unlockAfterVote(), 0);
    }

    function _usdcSum() internal view returns (uint256 sum) {
        MockUSDC usdc = handler.usdc();
        sum = usdc.balanceOf(address(handler.cruiseControl()));
        sum += usdc.balanceOf(address(handler.degenDriver()));
        sum += usdc.balanceOf(address(handler.cruise()));
        sum += usdc.balanceOf(address(handler.highway()));
        sum += usdc.balanceOf(address(handler.autobahn()));
        sum += usdc.balanceOf(address(handler.drift()));
        sum += usdc.balanceOf(address(handler.splitter()));
        sum += usdc.balanceOf(address(handler.pool()));
        sum += usdc.balanceOf(address(handler.dvrFaucet()));
        sum += usdc.balanceOf(address(handler.usdcFaucet()));
        sum += usdc.balanceOf(address(handler.driverVote()));
    }

    function _dvrSum() internal view returns (uint256 sum) {
        DriverToken token = handler.token();
        sum = token.balanceOf(address(handler.cruiseControl()));
        sum += token.balanceOf(address(handler.degenDriver()));
        sum += token.balanceOf(address(handler.cruise()));
        sum += token.balanceOf(address(handler.highway()));
        sum += token.balanceOf(address(handler.autobahn()));
        sum += token.balanceOf(address(handler.drift()));
        sum += token.balanceOf(address(handler.splitter()));
        sum += token.balanceOf(address(handler.pool()));
        sum += token.balanceOf(address(handler.dvrFaucet()));
        sum += token.balanceOf(address(handler.usdcFaucet()));
        sum += token.balanceOf(address(handler.driverVote()));
    }
}

/// forge-config: default.invariant.depth = 100
contract ProtocolInvariantTest is ProtocolInvariantBase {
    function setUp() public {
        _bind(new ProtocolHandler(false));
        bytes4[] memory selectors = new bytes4[](12);
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
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }
}
