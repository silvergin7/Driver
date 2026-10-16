// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {IOfficialPool} from "../../src/interfaces/IOfficialPool.sol";

contract OfficialPoolFuzzTest is Test {
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;
    uint256 internal constant ALICE_DVR = 200_000 * 10 ** 18;
    uint256 internal constant ALICE_USDC = 100_000 * 10 ** 6;

    DriverToken internal token;
    MockUSDC internal usdc;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        token = new DriverToken(owner);
        usdc = new MockUSDC(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, 100);

        vm.startPrank(owner);
        token.mint(owner, SEED_DVR);
        usdc.mint(owner, SEED_USDC);
        token.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        splitter.setPool(address(pool));
        pool.addLiquidity(SEED_DVR, SEED_USDC);
        token.mint(alice, ALICE_DVR);
        usdc.mint(alice, ALICE_USDC);
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_BuyExactInputDoesNotDecreaseK(uint256 amountIn, uint256 taxBps) public {
        _setTax(taxBps);
        amountIn = bound(amountIn, 10_000, pool.reserveUsdc() / 10);
        _assertSwap(IOfficialPool.Direction.Buy, true, amountIn);
    }

    function testFuzz_SellExactInputDoesNotDecreaseK(uint256 amountIn, uint256 taxBps) public {
        _setTax(taxBps);
        amountIn = bound(amountIn, 1e15, pool.reserveDvr() / 10);
        _assertSwap(IOfficialPool.Direction.Sell, true, amountIn);
    }

    function testFuzz_BuyExactOutputDoesNotDecreaseK(uint256 amountOut, uint256 taxBps) public {
        _setTax(taxBps);
        amountOut = bound(amountOut, 1e12, pool.reserveDvr() / 10);
        _assertSwap(IOfficialPool.Direction.Buy, false, amountOut);
    }

    function testFuzz_SellExactOutputDoesNotDecreaseK(uint256 amountOut, uint256 taxBps) public {
        _setTax(taxBps);
        amountOut = bound(amountOut, 1_000, pool.reserveUsdc() / 10);
        _assertSwap(IOfficialPool.Direction.Sell, false, amountOut);
    }

    function testFuzz_SetTaxBpsWithinMaximum(uint256 taxBps) public {
        taxBps = bound(taxBps, 0, pool.MAX_TAX_BPS());

        vm.expectEmit(false, false, false, true, address(pool));
        emit OfficialPool.TaxBpsUpdated(pool.taxBps(), taxBps);
        vm.prank(owner);
        pool.setTaxBps(taxBps);

        assertEq(pool.taxBps(), taxBps);
        assertLe(pool.taxBps(), pool.MAX_TAX_BPS());
    }

    function testFuzz_RevertWhen_SetTaxBpsAboveMaximum(uint256 taxBps) public {
        taxBps = bound(taxBps, pool.MAX_TAX_BPS() + 1, type(uint256).max);
        uint256 reserveDvr = pool.reserveDvr();
        uint256 reserveUsdc = pool.reserveUsdc();

        vm.expectRevert(
            abi.encodeWithSelector(OfficialPool.OfficialPool__TaxAboveMaximum.selector, taxBps, pool.MAX_TAX_BPS())
        );
        vm.prank(owner);
        pool.setTaxBps(taxBps);

        assertEq(pool.taxBps(), 100);
        assertEq(pool.reserveDvr(), reserveDvr);
        assertEq(pool.reserveUsdc(), reserveUsdc);
    }

    function _setTax(uint256 taxBps) private {
        taxBps = bound(taxBps, 0, pool.MAX_TAX_BPS());
        vm.prank(owner);
        pool.setTaxBps(taxBps);
    }

    function _assertSwap(IOfficialPool.Direction direction, bool exactInput, uint256 amount) private {
        uint256 kBefore = pool.reserveDvr() * pool.reserveUsdc();
        uint256 splitterBefore = usdc.balanceOf(address(splitter));
        uint256 quotedOut;
        uint256 quotedIn;
        uint256 quotedTax;
        uint256 got;

        if (exactInput) {
            (quotedOut, quotedTax) = pool.quoteExactInput(direction, amount);
            vm.prank(alice);
            got = pool.swapExactInput(direction, amount, 0, block.timestamp);
            assertEq(got, quotedOut);
        } else {
            (quotedIn, quotedTax) = pool.quoteExactOutput(direction, amount);
            vm.prank(alice);
            got = pool.swapExactOutput(direction, amount, type(uint256).max, block.timestamp);
            assertEq(got, quotedIn);
        }

        assertGe(pool.reserveDvr() * pool.reserveUsdc(), kBefore);
        if (pool.taxBps() == 0) {
            assertEq(quotedTax, 0);
            assertEq(usdc.balanceOf(address(splitter)), splitterBefore);
        } else {
            assertGt(quotedTax, 0);
            assertEq(usdc.balanceOf(address(splitter)), splitterBefore + quotedTax);
        }
    }
}
