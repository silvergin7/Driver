// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DriverToken} from "../../../src/DriverToken.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";
import {OfficialPool} from "../../../src/OfficialPool.sol";
import {TaxSplitter} from "../../../src/TaxSplitter.sol";
import {IOfficialPool} from "../../../src/interfaces/IOfficialPool.sol";

contract OfficialPoolHandler is Test {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant FUND_BPS = 4_000;
    uint256 internal constant MIN_BUY_IN = 10_000;
    uint256 internal constant MIN_SELL_IN = 1e15;
    uint256 internal constant MIN_BUY_OUT = 1e12;
    uint256 internal constant MIN_SELL_OUT = 1_000;
    uint256 internal constant MIN_ADD_DVR = 1e15;
    uint256 internal constant MIN_ADD_USDC = 1_000;

    DriverToken internal immutable i_token;
    MockUSDC internal immutable i_usdc;
    OfficialPool internal immutable i_pool;
    TaxSplitter internal immutable i_splitter;
    address internal immutable i_owner;

    uint256 public s_ghostReserveDvr;
    uint256 public s_ghostReserveUsdc;
    uint256 public s_ghostPreviousK;
    uint256 public s_ghostTaxBps;
    uint256 public s_ghostTax1;
    uint256 public s_ghostTax2;
    uint256 public s_ghostTax3;
    uint256 public s_ghostDonatedDvr;
    uint256 public s_ghostDonatedUsdc;
    uint256 public s_ghostDonatedToSplitter;
    uint256 public s_ghostBuyExactInputs;
    uint256 public s_ghostBuyExactOutputs;
    uint256 public s_ghostSellExactInputs;
    uint256 public s_ghostSellExactOutputs;
    uint256 public s_ghostAdds;
    uint256 public s_ghostDonations;

    struct Quote {
        uint256 amountIn;
        uint256 amountOut;
        uint256 usdcTax;
        uint256 newReserveDvr;
        uint256 newReserveUsdc;
        bool ok;
    }

    constructor(
        DriverToken token,
        MockUSDC usdc,
        OfficialPool pool,
        TaxSplitter splitter,
        address owner_,
        uint256 seedDvr,
        uint256 seedUsdc,
        uint256 initialTaxBps
    ) {
        i_token = token;
        i_usdc = usdc;
        i_pool = pool;
        i_splitter = splitter;
        i_owner = owner_;

        vm.startPrank(owner_);
        token.mint(owner_, seedDvr);
        usdc.mint(owner_, seedUsdc);
        token.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        splitter.setPool(address(pool));
        pool.addLiquidity(seedDvr, seedUsdc);
        vm.stopPrank();

        token.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);

        s_ghostReserveDvr = seedDvr;
        s_ghostReserveUsdc = seedUsdc;
        s_ghostPreviousK = seedDvr * seedUsdc;
        s_ghostTaxBps = initialTaxBps;
    }

    function buyExactInput(uint256 amountIn) external {
        (uint256 amount, bool inRange) = _boundOrSkip(amountIn, MIN_BUY_IN, s_ghostReserveUsdc / 10);
        if (!inRange) return;

        Quote memory quote = _quoteBuyExactInput(amount);
        if (!quote.ok) return;
        if (!_fundUsdc(address(this), quote.amountIn)) return;

        uint256 got = i_pool.swapExactInput(IOfficialPool.Direction.Buy, quote.amountIn, 0, block.timestamp);
        assertEq(got, quote.amountOut);
        _apply(quote);
        s_ghostBuyExactInputs += 1;
    }

    function buyExactOutput(uint256 amountOut) external {
        (uint256 amount, bool inRange) = _boundOrSkip(amountOut, MIN_BUY_OUT, s_ghostReserveDvr / 10);
        if (!inRange) return;

        Quote memory quote = _quoteBuyExactOutput(amount);
        if (!quote.ok) return;
        if (!_fundUsdc(address(this), quote.amountIn)) return;

        uint256 got =
            i_pool.swapExactOutput(IOfficialPool.Direction.Buy, quote.amountOut, type(uint256).max, block.timestamp);
        assertEq(got, quote.amountIn);
        _apply(quote);
        s_ghostBuyExactOutputs += 1;
    }

    function sellExactInput(uint256 amountIn) external {
        (uint256 amount, bool inRange) = _boundOrSkip(amountIn, MIN_SELL_IN, s_ghostReserveDvr / 10);
        if (!inRange) return;

        Quote memory quote = _quoteSellExactInput(amount);
        if (!quote.ok) return;
        if (!_fundDvr(address(this), quote.amountIn)) return;

        uint256 got = i_pool.swapExactInput(IOfficialPool.Direction.Sell, quote.amountIn, 0, block.timestamp);
        assertEq(got, quote.amountOut);
        _apply(quote);
        s_ghostSellExactInputs += 1;
    }

    function sellExactOutput(uint256 amountOut) external {
        (uint256 amount, bool inRange) = _boundOrSkip(amountOut, MIN_SELL_OUT, s_ghostReserveUsdc / 10);
        if (!inRange) return;

        Quote memory quote = _quoteSellExactOutput(amount);
        if (!quote.ok) return;
        if (!_fundDvr(address(this), quote.amountIn)) return;

        uint256 got =
            i_pool.swapExactOutput(IOfficialPool.Direction.Sell, quote.amountOut, type(uint256).max, block.timestamp);
        assertEq(got, quote.amountIn);
        _apply(quote);
        s_ghostSellExactOutputs += 1;
    }

    function addLiquidity(uint256 dvrAmount, uint256 usdcAmount) external {
        (uint256 dvrOffer, bool dvrOk) = _boundOrSkip(dvrAmount, MIN_ADD_DVR, s_ghostReserveDvr / 100);
        if (!dvrOk) return;
        (uint256 usdcOffer, bool usdcOk) = _boundOrSkip(usdcAmount, MIN_ADD_USDC, s_ghostReserveUsdc / 100);
        if (!usdcOk) return;

        (uint256 dvrUsed, uint256 usdcUsed) = _liquidityUsed(dvrOffer, usdcOffer);
        if (dvrUsed == 0 || usdcUsed == 0) return;
        if (!_fundDvr(i_owner, dvrUsed)) return;
        if (!_fundUsdc(i_owner, usdcUsed)) return;

        vm.prank(i_owner);
        (uint256 gotDvr, uint256 gotUsdc) = i_pool.addLiquidity(dvrOffer, usdcOffer);

        assertEq(gotDvr, dvrUsed);
        assertEq(gotUsdc, usdcUsed);
        _snapshotK();
        s_ghostReserveDvr += dvrUsed;
        s_ghostReserveUsdc += usdcUsed;
        s_ghostAdds += 1;
    }

    function donate(uint256 amount, uint256 kind) external {
        uint256 which = kind % 3;
        if (which == 0) {
            (uint256 dvrAmount, bool ok) = _boundOrSkip(amount, 1, 1e18);
            if (!ok) return;
            if (!_fundDvr(address(this), dvrAmount)) return;
            assertTrue(i_token.transfer(address(i_pool), dvrAmount));
            s_ghostDonatedDvr += dvrAmount;
        } else if (which == 1) {
            (uint256 usdcAmount, bool ok) = _boundOrSkip(amount, 1, 1e6);
            if (!ok) return;
            if (!_fundUsdc(address(this), usdcAmount)) return;
            assertTrue(i_usdc.transfer(address(i_pool), usdcAmount));
            s_ghostDonatedUsdc += usdcAmount;
        } else {
            (uint256 usdcAmount, bool ok) = _boundOrSkip(amount, 1, 1e6);
            if (!ok) return;
            if (!_fundUsdc(address(this), usdcAmount)) return;
            assertTrue(i_usdc.transfer(address(i_splitter), usdcAmount));
            s_ghostDonatedToSplitter += usdcAmount;
        }
        _snapshotK();
        s_ghostDonations += 1;
    }

    function setTaxBps(uint256 newTaxBps) external {
        newTaxBps = bound(newTaxBps, 0, i_pool.MAX_TAX_BPS());
        vm.prank(i_owner);
        i_pool.setTaxBps(newTaxBps);
        s_ghostTaxBps = newTaxBps;
        _snapshotK();
    }

    function _apply(Quote memory quote) private {
        _snapshotK();
        s_ghostReserveDvr = quote.newReserveDvr;
        s_ghostReserveUsdc = quote.newReserveUsdc;
        _creditTax(quote.usdcTax);
    }

    function _snapshotK() private {
        s_ghostPreviousK = s_ghostReserveDvr * s_ghostReserveUsdc;
    }

    function _creditTax(uint256 tax) private {
        if (tax == 0) return;
        uint256 fund1 = Math.mulDiv(tax, FUND_BPS, BPS_DENOMINATOR);
        uint256 fund2 = Math.mulDiv(tax, FUND_BPS, BPS_DENOMINATOR);
        s_ghostTax1 += fund1;
        s_ghostTax2 += fund2;
        s_ghostTax3 += tax - fund1 - fund2;
    }

    function _quoteBuyExactInput(uint256 amountIn) private view returns (Quote memory quote) {
        quote.amountIn = amountIn;
        quote.usdcTax = Math.mulDiv(amountIn, s_ghostTaxBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
        uint256 usdcToReserve = amountIn - quote.usdcTax;
        if (usdcToReserve == 0) return quote;
        quote.amountOut = Math.mulDiv(s_ghostReserveDvr, usdcToReserve, s_ghostReserveUsdc + usdcToReserve);
        if (quote.amountOut == 0 || quote.amountOut >= s_ghostReserveDvr) return quote;
        quote.newReserveDvr = s_ghostReserveDvr - quote.amountOut;
        quote.newReserveUsdc = s_ghostReserveUsdc + usdcToReserve;
        quote.ok = true;
    }

    function _quoteBuyExactOutput(uint256 amountOut) private view returns (Quote memory quote) {
        quote.amountOut = amountOut;
        if (amountOut >= s_ghostReserveDvr) return quote;
        uint256 usdcToReserve =
            Math.mulDiv(s_ghostReserveUsdc, amountOut, s_ghostReserveDvr - amountOut, Math.Rounding.Ceil);
        quote.amountIn =
            Math.mulDiv(usdcToReserve, BPS_DENOMINATOR, BPS_DENOMINATOR - s_ghostTaxBps, Math.Rounding.Ceil);
        quote.usdcTax = quote.amountIn - usdcToReserve;
        quote.newReserveDvr = s_ghostReserveDvr - amountOut;
        quote.newReserveUsdc = s_ghostReserveUsdc + usdcToReserve;
        quote.ok = true;
    }

    function _quoteSellExactInput(uint256 amountIn) private view returns (Quote memory quote) {
        quote.amountIn = amountIn;
        uint256 usdcGross = Math.mulDiv(s_ghostReserveUsdc, amountIn, s_ghostReserveDvr + amountIn);
        if (usdcGross == 0 || usdcGross >= s_ghostReserveUsdc) return quote;
        quote.usdcTax = Math.mulDiv(usdcGross, s_ghostTaxBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
        quote.amountOut = usdcGross - quote.usdcTax;
        if (quote.amountOut == 0) return quote;
        quote.newReserveDvr = s_ghostReserveDvr + amountIn;
        quote.newReserveUsdc = s_ghostReserveUsdc - usdcGross;
        quote.ok = true;
    }

    function _quoteSellExactOutput(uint256 amountOut) private view returns (Quote memory quote) {
        quote.amountOut = amountOut;
        quote.usdcTax = Math.mulDiv(amountOut, s_ghostTaxBps, BPS_DENOMINATOR - s_ghostTaxBps, Math.Rounding.Ceil);
        uint256 usdcGross = amountOut + quote.usdcTax;
        if (usdcGross >= s_ghostReserveUsdc) return quote;
        quote.amountIn = Math.mulDiv(s_ghostReserveDvr, usdcGross, s_ghostReserveUsdc - usdcGross, Math.Rounding.Ceil);
        if (quote.amountIn == 0) return quote;
        quote.newReserveDvr = s_ghostReserveDvr + quote.amountIn;
        quote.newReserveUsdc = s_ghostReserveUsdc - usdcGross;
        quote.ok = true;
    }

    function _liquidityUsed(uint256 dvrAmount, uint256 usdcAmount)
        private
        view
        returns (uint256 dvrUsed, uint256 usdcUsed)
    {
        uint256 usdcOptimal = Math.mulDiv(dvrAmount, s_ghostReserveUsdc, s_ghostReserveDvr);
        if (usdcOptimal <= usdcAmount) {
            if (usdcOptimal == 0) return (0, 0);
            return (dvrAmount, usdcOptimal);
        }
        uint256 dvrOptimal = Math.mulDiv(usdcAmount, s_ghostReserveDvr, s_ghostReserveUsdc);
        if (dvrOptimal == 0) return (0, 0);
        return (dvrOptimal, usdcAmount);
    }

    function _fundDvr(address to, uint256 amount) private returns (bool funded) {
        uint256 balance = i_token.balanceOf(to);
        if (balance >= amount) return true;
        uint256 need = amount - balance;
        if (need > i_token.MAX_SUPPLY() - i_token.totalMinted()) return false;
        vm.prank(i_owner);
        i_token.mint(to, need);
        return true;
    }

    function _fundUsdc(address to, uint256 amount) private returns (bool funded) {
        uint256 balance = i_usdc.balanceOf(to);
        if (balance >= amount) return true;
        vm.prank(i_owner);
        i_usdc.mint(to, amount - balance);
        return true;
    }

    function _boundOrSkip(uint256 value, uint256 min, uint256 max) private pure returns (uint256 bounded, bool ok) {
        if (min > max) return (0, false);
        return (bound(value, min, max), true);
    }
}
