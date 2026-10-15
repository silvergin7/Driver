// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {IOfficialPool} from "../../src/interfaces/IOfficialPool.sol";

contract OfficialPoolTest is Test {
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;
    uint256 internal constant ALICE_DVR = 100_000 * 10 ** 18;
    uint256 internal constant ALICE_USDC = 1_000_000 * 10 ** 6;
    uint256 internal constant OWNER_DVR = 100_000 * 10 ** 18;
    uint256 internal constant OWNER_USDC = 1_000_000 * 10 ** 6;

    uint256 internal constant BUY_100_DVR_OUT = 4_901_475_393_603_327_062_085;
    uint256 internal constant BUY_100_K = 3_585_000_000;
    uint256 internal constant BUY_ONE_K = 479_999_000_000_000_000_000_000;
    uint256 internal constant SELL_ONE_K = 480_001_000_000_000_000_000_000;
    uint256 internal constant SELL_USDC_K = 3_493_480_614;
    uint256 internal constant SELL_ONE_DVR_IN = 50_510_202_045_610_667_543;

    DriverToken internal token;
    MockUSDC internal usdc;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    event LiquidityAdded(uint256 dvrUsed, uint256 usdcUsed, uint256 reserveDvr, uint256 reserveUsdc);
    event TaxBpsUpdated(uint256 previousBps, uint256 newBps);

    function setUp() public {
        token = new DriverToken(owner);
        usdc = new MockUSDC(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, 100);

        vm.startPrank(owner);
        token.mint(owner, SEED_DVR + ALICE_DVR + OWNER_DVR);
        usdc.mint(owner, SEED_USDC + ALICE_USDC + OWNER_USDC);
        token.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        splitter.setPool(address(pool));
        pool.addLiquidity(SEED_DVR, SEED_USDC);
        token.transfer(alice, ALICE_DVR);
        usdc.transfer(alice, ALICE_USDC);
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function test_SeedSetsReservesAndPrice() public view {
        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(pool.reserveUsdc(), SEED_USDC);
        assertEq(pool.reserveUsdc() * 10 ** 18 / pool.reserveDvr(), 20_000);
        assertEq(pool.taxBps(), 100);
        assertEq(pool.MAX_TAX_BPS(), 300);
        assertEq(pool.BPS_DENOMINATOR(), 10_000);
        assertEq(address(pool.i_dvr()), address(token));
        assertEq(address(pool.i_usdc()), address(usdc));
        assertEq(address(pool.i_taxSplitter()), address(splitter));
        assertEq(splitter.pool(), address(pool));
        assertEq(pool.owner(), owner);
        _assertSolvent();
    }

    function test_RevertWhen_ConstructorAddressIsZero() public {
        vm.expectRevert(OfficialPool.OfficialPool__ZeroAddress.selector);
        new OfficialPool(DriverToken(address(0)), usdc, splitter, owner, 100);

        vm.expectRevert(OfficialPool.OfficialPool__ZeroAddress.selector);
        new OfficialPool(token, MockUSDC(address(0)), splitter, owner, 100);

        vm.expectRevert(OfficialPool.OfficialPool__ZeroAddress.selector);
        new OfficialPool(token, usdc, TaxSplitter(address(0)), owner, 100);

        _assertSeedUntouched();
    }

    function test_RevertWhen_InitialOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new OfficialPool(token, usdc, splitter, address(0), 100);
    }

    function test_ConstructorAcceptsZeroTaxAndMaximumTax() public {
        OfficialPool zeroTax = new OfficialPool(token, usdc, splitter, owner, 0);
        OfficialPool maxTax = new OfficialPool(token, usdc, splitter, owner, 300);

        assertEq(zeroTax.taxBps(), 0);
        assertEq(maxTax.taxBps(), 300);
    }

    function test_RevertWhen_InitialTaxIsAboveMaximum() public {
        vm.expectRevert(abi.encodeWithSelector(OfficialPool.OfficialPool__TaxAboveMaximum.selector, 301, 300));
        new OfficialPool(token, usdc, splitter, owner, 301);
    }

    function test_BuyExactInputOfOneHundredUsdc() public {
        uint256 kBefore = _k();
        (uint256 quotedOut, uint256 quotedTax) = pool.quoteExactInput(IOfficialPool.Direction.Buy, 100_000_000);
        assertEq(quotedOut, BUY_100_DVR_OUT);
        assertEq(quotedTax, 1_000_000);

        vm.expectEmit(address(pool));
        emit IOfficialPool.Swapped(alice, IOfficialPool.Direction.Buy, 100_000_000, BUY_100_DVR_OUT, 1_000_000);

        vm.prank(alice);
        uint256 dvrOut = pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, BUY_100_DVR_OUT, _deadline());

        assertEq(dvrOut, BUY_100_DVR_OUT);
        assertEq(pool.reserveDvr(), SEED_DVR - BUY_100_DVR_OUT);
        assertEq(pool.reserveUsdc(), SEED_USDC + 99_000_000);
        assertEq(_k(), kBefore + BUY_100_K);
        assertEq(token.balanceOf(alice), ALICE_DVR + BUY_100_DVR_OUT);
        assertEq(usdc.balanceOf(alice), ALICE_USDC - 100_000_000);
        assertEq(usdc.balanceOf(address(splitter)), 1_000_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 200_000);
        assertEq(usdc.allowance(address(pool), address(splitter)), 0);
        _assertSolvent();
    }

    function test_BuyExactInputCeilsTheExtraWei() public {
        uint256 kBefore = _k();
        (uint256 quotedOut, uint256 quotedTax) = pool.quoteExactInput(IOfficialPool.Direction.Buy, 100_000_001);
        assertEq(quotedOut, BUY_100_DVR_OUT);
        assertEq(quotedTax, 1_000_001);

        vm.prank(alice);
        uint256 dvrOut = pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_001, 0, _deadline());

        assertEq(dvrOut, BUY_100_DVR_OUT);
        assertEq(pool.reserveUsdc(), SEED_USDC + 99_000_000);
        assertEq(_k(), kBefore + BUY_100_K);
        assertEq(usdc.balanceOf(alice), ALICE_USDC - 100_000_001);
        assertEq(usdc.balanceOf(address(splitter)), 1_000_001);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 200_001);
        _assertSolvent();
    }

    function test_BuyExactOutputOfOneDvr() public {
        uint256 kBefore = _k();
        (uint256 quotedIn, uint256 quotedTax) = pool.quoteExactOutput(IOfficialPool.Direction.Buy, 10 ** 18);
        assertEq(quotedIn, 20_204);
        assertEq(quotedTax, 203);

        vm.prank(alice);
        uint256 usdcIn = pool.swapExactOutput(IOfficialPool.Direction.Buy, 10 ** 18, 20_204, _deadline());

        assertEq(usdcIn, 20_204);
        assertEq(token.balanceOf(alice), ALICE_DVR + 10 ** 18);
        assertEq(usdc.balanceOf(alice), ALICE_USDC - 20_204);
        assertEq(pool.reserveDvr(), SEED_DVR - 10 ** 18);
        assertEq(pool.reserveUsdc(), SEED_USDC + 20_001);
        assertEq(_k(), kBefore + BUY_ONE_K);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 81);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 81);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 41);
        assertEq(usdc.balanceOf(address(splitter)), 203);
        _assertSolvent();
    }

    function test_SellExactInputOfOneDvr() public {
        uint256 kBefore = _k();
        (uint256 quotedOut, uint256 quotedTax) = pool.quoteExactInput(IOfficialPool.Direction.Sell, 10 ** 18);
        assertEq(quotedOut, 19_799);
        assertEq(quotedTax, 200);

        vm.prank(alice);
        uint256 usdcOut = pool.swapExactInput(IOfficialPool.Direction.Sell, 10 ** 18, 19_799, _deadline());

        assertEq(usdcOut, 19_799);
        assertEq(token.balanceOf(alice), ALICE_DVR - 10 ** 18);
        assertEq(usdc.balanceOf(alice), ALICE_USDC + 19_799);
        assertEq(pool.reserveDvr(), SEED_DVR + 10 ** 18);
        assertEq(pool.reserveUsdc(), SEED_USDC - 19_999);
        assertEq(_k(), kBefore + SELL_ONE_K);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 80);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 80);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 40);
        assertEq(usdc.balanceOf(address(splitter)), 200);
        _assertSolvent();
    }

    function test_SellExactOutputOfOneUsdc() public {
        uint256 kBefore = _k();
        (uint256 quotedIn, uint256 quotedTax) = pool.quoteExactOutput(IOfficialPool.Direction.Sell, 1_000_000);
        assertEq(quotedIn, SELL_ONE_DVR_IN);
        assertEq(quotedTax, 10_102);
        assertEq(_ceil(1_010_102 * 100, 10_000), 10_102);

        vm.prank(alice);
        uint256 dvrIn = pool.swapExactOutput(IOfficialPool.Direction.Sell, 1_000_000, SELL_ONE_DVR_IN, _deadline());

        assertEq(dvrIn, SELL_ONE_DVR_IN);
        assertEq(usdc.balanceOf(alice), ALICE_USDC + 1_000_000);
        assertEq(token.balanceOf(alice), ALICE_DVR - SELL_ONE_DVR_IN);
        assertEq(pool.reserveDvr(), SEED_DVR + SELL_ONE_DVR_IN);
        assertEq(pool.reserveUsdc(), SEED_USDC - 1_010_102);
        assertEq(_k(), kBefore + SELL_USDC_K);
        assertEq(usdc.balanceOf(address(splitter)), 10_102);
        _assertSolvent();
    }

    function test_OwnerBuyPaysTheSameTax() public {
        vm.prank(owner);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, BUY_100_DVR_OUT, _deadline());

        assertEq(usdc.balanceOf(address(splitter)), 1_000_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 200_000);
        assertEq(token.balanceOf(owner), OWNER_DVR + BUY_100_DVR_OUT);
    }

    function test_SetTaxBpsZeroSkipsTheSplitter() public {
        vm.expectEmit(address(pool));
        emit TaxBpsUpdated(100, 0);
        vm.prank(owner);
        pool.setTaxBps(0);

        vm.prank(alice);
        uint256 dvrOut = pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, 0, _deadline());

        assertEq(pool.taxBps(), 0);
        assertGt(dvrOut, BUY_100_DVR_OUT);
        assertEq(pool.reserveUsdc(), SEED_USDC + 100_000_000);
        assertEq(usdc.balanceOf(address(splitter)), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 0);
    }

    function test_SetTaxBpsMaximum() public {
        vm.expectEmit(address(pool));
        emit TaxBpsUpdated(100, 300);
        vm.prank(owner);
        pool.setTaxBps(300);

        assertEq(pool.taxBps(), 300);
    }

    function test_SetTaxBpsSameValueEmits() public {
        vm.expectEmit(address(pool));
        emit TaxBpsUpdated(100, 100);
        vm.prank(owner);
        pool.setTaxBps(100);

        assertEq(pool.taxBps(), 100);
    }

    function test_RevertWhen_SetTaxBpsAboveMaximum() public {
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(OfficialPool.OfficialPool__TaxAboveMaximum.selector, 301, 300));
        vm.prank(owner);
        pool.setTaxBps(301);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(pool.taxBps(), 100);
    }

    function test_RevertWhen_SetTaxBpsCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.setTaxBps(0);

        assertEq(pool.taxBps(), 100);
    }

    function test_SwapSucceedsAtExactDeadline() public {
        vm.prank(alice);
        uint256 dvrOut = pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, 0, block.timestamp);

        assertEq(dvrOut, BUY_100_DVR_OUT);
    }

    function test_RevertWhen_DeadlineHasPassed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficialPool.OfficialPool__DeadlinePassed.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(alice);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, 0, block.timestamp - 1);

        assertEq(pool.reserveDvr(), SEED_DVR);
    }

    function test_DeadlineIgnoresTheDemoClock() public {
        DemoDriverClock clock = new DemoDriverClock(owner);
        vm.prank(owner);
        clock.advanceTime(30 days);
        assertEq(clock.currentTime(), block.timestamp + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficialPool.OfficialPool__DeadlinePassed.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(alice);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, 0, block.timestamp - 1);

        vm.prank(alice);
        uint256 dvrOut = pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, 0, block.timestamp);

        assertEq(dvrOut, BUY_100_DVR_OUT);
        assertEq(clock.currentTime(), block.timestamp + 30 days);
    }

    function test_RevertWhen_MinAmountOutIsTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficialPool.OfficialPool__InsufficientOutput.selector, BUY_100_DVR_OUT, BUY_100_DVR_OUT + 1
            )
        );
        vm.prank(alice);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, BUY_100_DVR_OUT + 1, _deadline());

        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(usdc.balanceOf(address(splitter)), 0);
    }

    function test_RevertWhen_MaxAmountInIsTooLow() public {
        vm.expectRevert(abi.encodeWithSelector(IOfficialPool.OfficialPool__ExcessiveInput.selector, 20_204, 20_203));
        vm.prank(alice);
        pool.swapExactOutput(IOfficialPool.Direction.Buy, 10 ** 18, 20_203, _deadline());

        assertEq(pool.reserveDvr(), SEED_DVR);
    }

    function test_RevertWhen_SwapOnEmptyPool() public {
        OfficialPool empty = new OfficialPool(token, usdc, splitter, owner, 100);
        uint256 deadline = _deadline();

        vm.startPrank(alice);
        vm.expectRevert(IOfficialPool.OfficialPool__InsufficientReserves.selector);
        empty.swapExactInput(IOfficialPool.Direction.Buy, 100_000_000, 0, deadline);
        vm.expectRevert(IOfficialPool.OfficialPool__InsufficientReserves.selector);
        empty.swapExactInput(IOfficialPool.Direction.Sell, 10 ** 18, 0, deadline);
        vm.expectRevert(IOfficialPool.OfficialPool__InsufficientReserves.selector);
        empty.swapExactOutput(IOfficialPool.Direction.Buy, 10 ** 18, type(uint256).max, deadline);
        vm.expectRevert(IOfficialPool.OfficialPool__InsufficientReserves.selector);
        empty.swapExactOutput(IOfficialPool.Direction.Sell, 1_000_000, type(uint256).max, deadline);
        vm.stopPrank();
    }

    function test_RevertWhen_AmountIsZero() public {
        uint256 deadline = _deadline();

        vm.startPrank(alice);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 0, 0, deadline);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        pool.swapExactInput(IOfficialPool.Direction.Sell, 0, 0, deadline);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        pool.swapExactOutput(IOfficialPool.Direction.Buy, 0, type(uint256).max, deadline);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        pool.swapExactOutput(IOfficialPool.Direction.Sell, 0, type(uint256).max, deadline);
        vm.stopPrank();

        _assertSeedUntouched();
    }

    function test_RevertWhen_SellGrossIsZeroOrConsumedByTax() public {
        uint256 zeroGross = 50_000_000_005_000;
        uint256 oneGross = 50_000_000_005_001;
        assertEq((SEED_USDC * zeroGross) / (SEED_DVR + zeroGross), 0);
        assertEq((SEED_USDC * oneGross) / (SEED_DVR + oneGross), 1);
        assertEq(_ceil(1 * 100, 10_000), 1);

        vm.startPrank(alice);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroOutput.selector);
        pool.swapExactInput(IOfficialPool.Direction.Sell, oneGross, 0, _deadline());
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroOutput.selector);
        pool.swapExactInput(IOfficialPool.Direction.Sell, zeroGross, 0, _deadline());
        vm.stopPrank();

        _assertSeedUntouched();
    }

    function test_RevertWhen_TinyPoolBuyRoundsToZero() public {
        OfficialPool tiny = new OfficialPool(token, usdc, splitter, owner, 100);
        vm.startPrank(owner);
        token.approve(address(tiny), type(uint256).max);
        usdc.approve(address(tiny), type(uint256).max);
        tiny.addLiquidity(1, 10_000 * 10 ** 6);
        vm.stopPrank();

        uint256 tax = _ceil(100 * 100, 10_000);
        uint256 toCurve = 100 - tax;
        assertEq(tax, 1);
        assertEq(toCurve, 99);
        assertEq((uint256(1) * toCurve) / (10_000 * 10 ** 6 + toCurve), 0);

        uint256 aliceDvr = token.balanceOf(alice);
        uint256 aliceUsdc = usdc.balanceOf(alice);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroOutput.selector);
        vm.prank(alice);
        tiny.swapExactInput(IOfficialPool.Direction.Buy, 100, 0, _deadline());

        assertEq(tiny.reserveDvr(), 1);
        assertEq(tiny.reserveUsdc(), 10_000 * 10 ** 6);
        assertEq(token.balanceOf(address(tiny)), 1);
        assertEq(usdc.balanceOf(address(tiny)), 10_000 * 10 ** 6);
        assertEq(token.balanceOf(alice), aliceDvr);
        assertEq(usdc.balanceOf(alice), aliceUsdc);

        uint256 ownerDvr = token.balanceOf(owner);
        uint256 ownerUsdc = usdc.balanceOf(owner);
        assertEq((uint256(1) * tiny.reserveDvr()) / tiny.reserveUsdc(), 0);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        vm.prank(owner);
        tiny.addLiquidity(10 ** 18, 1);

        assertEq(tiny.reserveDvr(), 1);
        assertEq(tiny.reserveUsdc(), 10_000 * 10 ** 6);
        assertEq(token.balanceOf(address(tiny)), 1);
        assertEq(usdc.balanceOf(address(tiny)), 10_000 * 10 ** 6);
        assertEq(token.balanceOf(owner), ownerDvr);
        assertEq(usdc.balanceOf(owner), ownerUsdc);
        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(pool.reserveUsdc(), SEED_USDC);
        assertEq(token.balanceOf(address(pool)), SEED_DVR);
        assertEq(usdc.balanceOf(address(pool)), SEED_USDC);
        assertEq(usdc.balanceOf(address(splitter)), 0);
    }

    function test_RevertWhen_ExactOutputConsumesAReserve() public {
        uint256 reserveDvr = pool.reserveDvr();
        uint256 deadline = _deadline();

        vm.startPrank(alice);
        vm.expectRevert(IOfficialPool.OfficialPool__InsufficientReserves.selector);
        pool.swapExactOutput(IOfficialPool.Direction.Buy, reserveDvr, type(uint256).max, deadline);
        vm.expectRevert(IOfficialPool.OfficialPool__InsufficientReserves.selector);
        pool.swapExactOutput(IOfficialPool.Direction.Sell, SEED_USDC, type(uint256).max, deadline);
        vm.stopPrank();

        _assertSeedUntouched();
    }

    function test_RevertWhen_AddLiquidityOnEmptyPoolIsZero() public {
        OfficialPool empty = new OfficialPool(token, usdc, splitter, owner, 100);
        uint256 ownerDvr = token.balanceOf(owner);
        uint256 ownerUsdc = usdc.balanceOf(owner);

        vm.startPrank(owner);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        empty.addLiquidity(0, 1);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        empty.addLiquidity(1, 0);
        vm.stopPrank();

        assertEq(empty.reserveDvr(), 0);
        assertEq(empty.reserveUsdc(), 0);
        assertEq(token.balanceOf(address(empty)), 0);
        assertEq(usdc.balanceOf(address(empty)), 0);
        assertEq(token.balanceOf(owner), ownerDvr);
        assertEq(usdc.balanceOf(owner), ownerUsdc);
        _assertSeedUntouched();
    }

    function test_RevertWhen_BuyInputIsConsumedByTax() public {
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        vm.prank(alice);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 1, 0, _deadline());

        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(usdc.balanceOf(alice), ALICE_USDC);
    }

    function test_RevertWhen_SellOutputRoundsToZero() public {
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroOutput.selector);
        vm.prank(alice);
        pool.swapExactInput(IOfficialPool.Direction.Sell, 1, 0, _deadline());

        assertEq(pool.reserveUsdc(), SEED_USDC);
        assertEq(token.balanceOf(alice), ALICE_DVR);
    }

    function test_DirectTransferDoesNotChangeReserves() public {
        vm.startPrank(alice);
        token.transfer(address(pool), 5 * 10 ** 18);
        usdc.transfer(address(pool), 5 * 10 ** 6);
        vm.stopPrank();

        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(pool.reserveUsdc(), SEED_USDC);
        assertEq(token.balanceOf(address(pool)), SEED_DVR + 5 * 10 ** 18);
        assertEq(usdc.balanceOf(address(pool)), SEED_USDC + 5 * 10 ** 6);
        assertEq(_k(), SEED_DVR * SEED_USDC);
    }

    function test_AddLiquidityTakesOnlyTheBalancedUsdc() public {
        uint256 ownerDvrBefore = token.balanceOf(owner);
        uint256 ownerUsdcBefore = usdc.balanceOf(owner);

        vm.expectEmit(address(pool));
        emit LiquidityAdded(10 ** 18, 20_000, SEED_DVR + 10 ** 18, SEED_USDC + 20_000);

        vm.prank(owner);
        (uint256 dvrUsed, uint256 usdcUsed) = pool.addLiquidity(10 ** 18, 100_000);

        assertEq(dvrUsed, 10 ** 18);
        assertEq(usdcUsed, 20_000);
        assertEq(pool.reserveDvr(), SEED_DVR + 10 ** 18);
        assertEq(pool.reserveUsdc(), SEED_USDC + 20_000);
        assertEq(pool.reserveUsdc() * 10 ** 18 / pool.reserveDvr(), 20_000);
        assertEq(token.balanceOf(owner), ownerDvrBefore - 10 ** 18);
        assertEq(usdc.balanceOf(owner), ownerUsdcBefore - 20_000);
        _assertSolvent();
    }

    function test_AddLiquidityTakesOnlyTheBalancedDvr() public {
        uint256 ownerDvrBefore = token.balanceOf(owner);

        vm.prank(owner);
        (uint256 dvrUsed, uint256 usdcUsed) = pool.addLiquidity(10 ** 18, 10_000);

        assertEq(dvrUsed, 5 * 10 ** 17);
        assertEq(usdcUsed, 10_000);
        assertEq(token.balanceOf(owner), ownerDvrBefore - 5 * 10 ** 17);
        assertEq(pool.reserveDvr(), SEED_DVR + 5 * 10 ** 17);
        assertEq(pool.reserveUsdc(), SEED_USDC + 10_000);
        _assertSolvent();
    }

    function test_RevertWhen_AddLiquidityAmountIsZero() public {
        vm.startPrank(owner);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        pool.addLiquidity(0, SEED_USDC);
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        pool.addLiquidity(SEED_DVR, 0);
        vm.stopPrank();

        assertEq(pool.reserveDvr(), SEED_DVR);
    }

    function test_RevertWhen_AddLiquidityRoundsToZero() public {
        vm.expectRevert(IOfficialPool.OfficialPool__ZeroAmount.selector);
        vm.prank(owner);
        pool.addLiquidity(1, 1);

        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(pool.reserveUsdc(), SEED_USDC);
    }

    function test_RevertWhen_AddLiquidityCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.addLiquidity(10 ** 18, 20_000);

        assertEq(pool.reserveDvr(), SEED_DVR);
    }

    function test_RevertWhen_RemoveLiquidityIsCalled() public {
        (bool ok,) = address(pool).call(abi.encodeWithSignature("removeLiquidity(uint256,uint256)", 1, 1));

        assertFalse(ok);
        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(pool.reserveUsdc(), SEED_USDC);
    }

    function _deadline() internal view returns (uint256 deadline) {
        deadline = block.timestamp + 1 hours;
    }

    function _k() internal view returns (uint256 product) {
        product = pool.reserveDvr() * pool.reserveUsdc();
    }

    function _ceil(uint256 numerator, uint256 denominator) internal pure returns (uint256 quotient) {
        quotient = (numerator + denominator - 1) / denominator;
    }

    function _assertSolvent() internal view {
        assertEq(token.balanceOf(address(pool)), pool.reserveDvr());
        assertEq(usdc.balanceOf(address(pool)), pool.reserveUsdc());
    }

    function _assertSeedUntouched() internal view {
        assertEq(pool.reserveDvr(), SEED_DVR);
        assertEq(pool.reserveUsdc(), SEED_USDC);
        assertEq(token.balanceOf(address(pool)), SEED_DVR);
        assertEq(usdc.balanceOf(address(pool)), SEED_USDC);
        assertEq(token.balanceOf(alice), ALICE_DVR);
        assertEq(usdc.balanceOf(alice), ALICE_USDC);
        assertEq(token.balanceOf(owner), OWNER_DVR);
        assertEq(usdc.balanceOf(owner), OWNER_USDC);
        assertEq(usdc.balanceOf(address(splitter)), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 0);
    }
}
