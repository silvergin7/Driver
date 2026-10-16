// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {OfficialPoolHandler} from "./handlers/OfficialPoolHandler.sol";

contract OfficialPoolInvariantTest is Test {
    uint256 internal constant SEED_DVR = 100_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 2_000 * 10 ** 6;
    uint256 internal constant INITIAL_TAX_BPS = 100;
    uint256 internal constant TRADER_DVR = 200_000 * 10 ** 18;
    uint256 internal constant TRADER_USDC = 50_000 * 10 ** 6;

    DriverToken internal token;
    MockUSDC internal usdc;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    OfficialPoolHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        token = new DriverToken(owner);
        usdc = new MockUSDC(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, INITIAL_TAX_BPS);
        handler = new OfficialPoolHandler(token, usdc, pool, splitter, owner, SEED_DVR, SEED_USDC, INITIAL_TAX_BPS);

        vm.startPrank(owner);
        token.mint(address(handler), TRADER_DVR);
        usdc.mint(address(handler), TRADER_USDC);
        vm.stopPrank();

        excludeContract(address(token));
        excludeContract(address(usdc));
        excludeContract(address(pool));
        excludeContract(address(splitter));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.buyExactInput.selector;
        selectors[1] = handler.buyExactOutput.selector;
        selectors[2] = handler.sellExactInput.selector;
        selectors[3] = handler.sellExactOutput.selector;
        selectors[4] = handler.addLiquidity.selector;
        selectors[5] = handler.donate.selector;
        selectors[6] = handler.setTaxBps.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_KNeverDecreases() public view {
        uint256 reserveDvr = pool.reserveDvr();
        uint256 reserveUsdc = pool.reserveUsdc();
        assertEq(reserveDvr, handler.s_ghostReserveDvr());
        assertEq(reserveUsdc, handler.s_ghostReserveUsdc());
        assertGe(reserveDvr * reserveUsdc, handler.s_ghostPreviousK());
    }

    function invariant_BalancesMatchReservesPlusDonations() public view {
        assertEq(token.balanceOf(address(pool)), handler.s_ghostReserveDvr() + handler.s_ghostDonatedDvr());
        assertEq(usdc.balanceOf(address(pool)), handler.s_ghostReserveUsdc() + handler.s_ghostDonatedUsdc());
    }

    function invariant_TaxBucketsMatchGhosts() public view {
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), handler.s_ghostTax1());
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), handler.s_ghostTax2());
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), handler.s_ghostTax3());
        uint256 buckets = handler.s_ghostTax1() + handler.s_ghostTax2() + handler.s_ghostTax3();
        assertEq(buckets, usdc.balanceOf(address(splitter)) - handler.s_ghostDonatedToSplitter());
    }

    function invariant_TaxBpsMatchesGhost() public view {
        assertEq(pool.taxBps(), handler.s_ghostTaxBps());
        assertLe(pool.taxBps(), pool.MAX_TAX_BPS());
    }

    function afterInvariant() public view {
        assertGt(handler.s_ghostBuyExactInputs(), 0);
        assertGt(handler.s_ghostBuyExactOutputs(), 0);
        assertGt(handler.s_ghostSellExactInputs(), 0);
        assertGt(handler.s_ghostSellExactOutputs(), 0);
        assertGt(handler.s_ghostTax1() + handler.s_ghostTax2() + handler.s_ghostTax3(), 0);
        assertGt(handler.s_ghostAdds(), 0);
        assertGt(handler.s_ghostDonations(), 0);
    }
}
