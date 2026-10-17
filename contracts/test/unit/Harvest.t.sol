// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {IOfficialPool} from "../../src/interfaces/IOfficialPool.sol";
import {ITreasuryFund} from "../../src/interfaces/ITreasuryFund.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DegenDriver} from "../../src/DegenDriver.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverClock} from "../../src/DriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../src/TreasuryFund.sol";
import {
    FixedFarm,
    IdleBallot,
    MappedBallot,
    ReenteringPool,
    RejectingPool,
    RevertingBallot
} from "../mocks/HarvestMocks.sol";

contract HarvestTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;

    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;
    uint256 internal constant PRINCIPAL = 15_000 * 10 ** 6;
    uint256 internal constant APR = 500;
    uint256 internal constant REWARDS = 61_643_835;
    uint256 internal constant COMPOUND = 30_821_918;
    uint256 internal constant BUYBACK = 30_821_917;
    uint256 internal constant BUY_TAX = 308_220;
    uint256 internal constant DVR_OUT = 1_521_043_583_696_329_605_839;
    uint256 internal constant K_DELTA = 5_299_323_217;
    uint256 internal constant FUND_SHARE = 123_288;
    uint256 internal constant FUND3_SHARE = 61_644;
    uint256 internal constant REWARDS_2 = 61_770_501;
    uint256 internal constant COMPOUND_2 = 30_885_251;
    uint256 internal constant BUYBACK_2 = 30_885_250;
    uint256 internal constant BUY_TAX_2 = 308_853;
    uint256 internal constant DVR_OUT_2 = 1_514_914_420_319_134_685_061;
    uint256 internal constant BURNED_TOTAL = 3_035_958_004_015_464_290_900;
    uint256 internal constant PRINCIPAL_AFTER = 15_030_821_918;
    uint256 internal constant PRINCIPAL_END = 15_061_830_457;
    uint256 internal constant HELD_REWARDS = 123_287_670;
    uint256 internal constant HELD_DVR_OUT = 3_032_861_038_836_992_348_847;
    uint256 internal constant TWO_UNIT_DVR = 49_999_999_995_000;

    MockUSDC internal usdc;
    DriverToken internal token;
    DemoDriverClock internal clock;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    RoundSchedule internal schedule;
    MockFarm internal farm;
    CruiseControl internal fund;
    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC(owner);
        token = new DriverToken(owner);
        clock = new DemoDriverClock(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, 100);
        schedule = new RoundSchedule(clock, 30 days);
        vm.prank(owner);
        splitter.setPool(address(pool));
        farm = new MockFarm(usdc, clock, APR, owner);
        fund = new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, _one(farm), owner);

        vm.startPrank(owner);
        token.mint(owner, SEED_DVR);
        usdc.mint(owner, 50_000_000 * 10 ** 6);
        token.approve(address(pool), SEED_DVR);
        usdc.approve(address(pool), SEED_USDC);
        pool.addLiquidity(SEED_DVR, SEED_USDC);
        usdc.approve(address(farm), 1_000_000 * 10 ** 6);
        farm.fundRewards(1_000_000 * 10 ** 6);
        farm.addDepositor(address(fund));
        usdc.approve(address(fund), PRINCIPAL);
        fund.supply(PRINCIPAL);
        fund.setStrategy(farm);
        fund.deposit(PRINCIPAL);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(fund));
        vm.stopPrank();
    }

    function test_ViewsBeforeTheFirstRoundCloses() public {
        _assertIdleRound();
        vm.prank(owner);
        vm.expectRevert(RoundSchedule.RoundSchedule__NoClosedRound.selector);
        fund.harvest(0);
        _assertIdleRound();
    }

    function test_RevertWhen_HarvestCallerIsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        fund.harvest(0);

        _skip(30 days);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        fund.harvest(0);
        (bool ready,) = fund.harvestableRound();
        assertTrue(ready);
    }

    function test_FirstHarvestBuysAndBurnsTheWorkedAmounts() public {
        _skip(30 days);
        (bool ready, uint256 roundId) = fund.harvestableRound();
        assertTrue(ready);
        assertEq(roundId, 0);
        uint256 kBefore = _k();
        uint256 supplyBefore = token.totalSupply();
        uint256 mintedBefore = token.totalMinted();

        vm.expectCall(
            address(pool),
            abi.encodeCall(pool.swapExactInput, (IOfficialPool.Direction.Buy, BUYBACK, 0, block.timestamp))
        );
        vm.expectEmit(address(farm));
        emit IMockFarm.RewardsClaimed(address(fund), REWARDS, 0);
        vm.expectEmit(address(fund));
        emit TreasuryFund.CapitalDeployed(address(farm), COMPOUND, 0);
        vm.expectEmit(address(pool));
        emit IOfficialPool.Swapped(address(fund), IOfficialPool.Direction.Buy, BUYBACK, DVR_OUT, BUY_TAX);
        vm.expectEmit(true, false, false, true, address(fund));
        emit TreasuryFund.Harvested(0, 0, REWARDS, COMPOUND, BUYBACK, DVR_OUT, 0);

        vm.prank(owner);
        fund.harvest(0);

        assertEq(fund.principal(), PRINCIPAL_AFTER);
        assertEq(fund.idle(), 0);
        assertEq(fund.heldRewards(), 0);
        assertEq(fund.pendingBuyback(), 0);
        assertEq(fund.dvrBoughtBack(), DVR_OUT);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(token.totalSupply(), supplyBefore - DVR_OUT);
        assertEq(token.totalMinted(), mintedBefore);
        assertEq(_k(), kBefore + K_DELTA);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), FUND_SHARE);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), FUND_SHARE);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), FUND3_SHARE);
        assertEq(usdc.allowance(address(fund), address(pool)), 0);
        assertEq(usdc.allowance(address(fund), address(farm)), 0);
        _assertHarvest(0, true, 0, 0, REWARDS, COMPOUND, BUYBACK, DVR_OUT, 0);
        (bool readyAfter, uint256 openRound) = fund.harvestableRound();
        assertFalse(readyAfter);
        assertEq(openRound, 1);
    }

    function test_SecondHarvestCompoundsTheTaxAndAddsTheBurn() public {
        _skip(30 days);
        vm.prank(owner);
        fund.harvest(0);
        _skip(30 days);

        vm.expectEmit(true, true, false, true, address(splitter));
        emit TaxSplitter.TaxReleased(TaxSplitter.FundId.Fund1, address(fund), FUND_SHARE);
        vm.expectEmit(address(farm));
        emit IMockFarm.RewardsClaimed(address(fund), REWARDS_2, 0);
        vm.expectEmit(address(fund));
        emit TreasuryFund.CapitalDeployed(address(farm), COMPOUND_2, 0);
        vm.expectEmit(address(pool));
        emit IOfficialPool.Swapped(address(fund), IOfficialPool.Direction.Buy, BUYBACK_2, DVR_OUT_2, BUY_TAX_2);
        vm.expectEmit(address(fund));
        emit TreasuryFund.CapitalDeployed(address(farm), FUND_SHARE, 0);
        vm.expectEmit(true, false, false, true, address(fund));
        emit TreasuryFund.Harvested(1, FUND_SHARE, REWARDS_2, COMPOUND_2, BUYBACK_2, DVR_OUT_2, 0);

        vm.prank(owner);
        fund.harvest(0);

        assertEq(fund.principal(), PRINCIPAL_END);
        assertEq(fund.dvrBoughtBack(), BURNED_TOTAL);
        assertEq(fund.pendingBuyback(), 0);
        _assertHarvest(1, true, 1, FUND_SHARE, REWARDS_2, COMPOUND_2, BUYBACK_2, DVR_OUT_2, 0);
    }

    function test_CatchUpAppliesOnlyTheLatestClosedRound() public {
        _skip(90 days);
        (bool ready, uint256 roundId) = fund.harvestableRound();
        assertTrue(ready);
        assertEq(roundId, 2);

        vm.prank(owner);
        fund.harvest(0);

        _assertHarvestRound(2);
        (bool readyAfter, uint256 openRound) = fund.harvestableRound();
        assertFalse(readyAfter);
        assertEq(openRound, 3);
        assertEq(fund.pendingBuyback(), 0);
        assertEq(fund.dvrBoughtBack(), fund.lastHarvest().dvrBurned);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__RoundAlreadyHarvested.selector, 2));
        fund.harvest(0);
    }

    function test_WarpOnAProductionClockClosesTheRound() public {
        DriverClock production = new DriverClock();
        RoundSchedule productionSchedule = new RoundSchedule(production, 30 days);
        MockFarm productionFarm = new MockFarm(usdc, production, APR, owner);
        CruiseControl productionFund = new CruiseControl(
            usdc, production, productionSchedule, splitter, pool, SHARE_1, SHARE_2, _one(productionFarm), owner
        );
        vm.startPrank(owner);
        usdc.approve(address(productionFarm), 1_000_000 * 10 ** 6);
        productionFarm.fundRewards(1_000_000 * 10 ** 6);
        productionFarm.addDepositor(address(productionFund));
        usdc.approve(address(productionFund), PRINCIPAL);
        productionFund.supply(PRINCIPAL);
        productionFund.setStrategy(productionFarm);
        productionFund.deposit(PRINCIPAL);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);
        vm.prank(owner);
        productionFund.harvest(0);

        assertEq(productionFund.dvrBoughtBack(), DVR_OUT);
        _assertFundRound(productionFund, 0);
    }

    function test_SlippageLeavesTheRoundHarvestable() public {
        _skip(30 days);
        uint256 kBefore = _k();
        uint256 accruedBefore = farm.accrued(address(fund));

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IOfficialPool.OfficialPool__InsufficientOutput.selector, DVR_OUT, DVR_OUT + 1)
        );
        fund.harvest(DVR_OUT + 1);

        (bool ready, uint256 roundId) = fund.harvestableRound();
        assertTrue(ready);
        assertEq(roundId, 0);
        (bool harvested,) = fund.lastHarvestedRound();
        assertFalse(harvested);
        assertEq(farm.accrued(address(fund)), accruedBefore);
        assertEq(fund.principal(), PRINCIPAL);
        assertEq(_k(), kBefore);
        assertEq(fund.dvrBoughtBack(), 0);
    }

    function test_DirectSwapStillRejectsAPassedDeadline() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOfficialPool.OfficialPool__DeadlinePassed.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(owner);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100 * 10 ** 6, 0, block.timestamp - 1);
    }

    function test_ZeroRewardsSkipTheSwap() public {
        MockFarm empty = new MockFarm(usdc, clock, APR, owner);
        CruiseControl idleFund =
            new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, _one(empty), owner);
        vm.startPrank(owner);
        empty.addDepositor(address(idleFund));
        idleFund.setStrategy(empty);
        vm.stopPrank();
        _skip(30 days);
        uint256 kBefore = _k();

        vm.recordLogs();
        vm.prank(owner);
        idleFund.harvest(type(uint256).max);

        assertEq(idleFund.dvrBoughtBack(), 0);
        assertEq(idleFund.pendingBuyback(), 0);
        assertEq(_k(), kBefore);
        assertEq(idleFund.lastHarvest().rewards, 0);
        assertFalse(_saw(keccak256("RewardsClaimed(address,uint256,uint256)")));
        assertFalse(_saw(keccak256("Swapped(address,uint8,uint256,uint256,uint256)")));
    }

    function test_HeldRewardsFromASwitchAreSplit() public {
        MockFarm other = new MockFarm(usdc, clock, APR, owner);
        IMockFarm[] memory farms = new IMockFarm[](2);
        farms[0] = farm;
        farms[1] = other;
        CruiseControl switching =
            new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, farms, owner);
        vm.startPrank(owner);
        farm.addDepositor(address(switching));
        other.addDepositor(address(switching));
        usdc.approve(address(other), 1_000_000 * 10 ** 6);
        other.fundRewards(1_000_000 * 10 ** 6);
        usdc.approve(address(switching), PRINCIPAL);
        switching.supply(PRINCIPAL);
        switching.setStrategy(farm);
        switching.deposit(PRINCIPAL);
        vm.stopPrank();
        _skip(30 days);
        vm.prank(owner);
        switching.setStrategy(other);
        assertEq(switching.heldRewards(), REWARDS);
        _skip(30 days);

        vm.prank(owner);
        switching.harvest(0);

        assertEq(switching.heldRewards(), 0);
        assertEq(switching.lastHarvest().rewards, HELD_REWARDS);
        assertEq(switching.lastHarvest().buybackSpent, REWARDS);
        assertEq(switching.lastHarvest().compounded, REWARDS);
        assertEq(switching.dvrBoughtBack(), HELD_DVR_OUT);
    }

    function test_DustBuyIsDeferredUntilALaterNonZeroHalf() public {
        (CruiseControl dust,) = _dustFund();
        vm.prank(owner);
        clock.advanceTime(1 days);
        uint256 kBefore = _k();

        vm.prank(owner);
        dust.harvest(type(uint256).max);

        assertEq(dust.pendingBuyback(), 1);
        assertEq(dust.dvrBoughtBack(), 0);
        assertEq(dust.principal(), 731);
        assertEq(_k(), kBefore);
        assertEq(dust.lastHarvest().rewards, 2);
        assertEq(dust.lastHarvest().buybackSpent, 0);
        assertEq(dust.lastHarvest().pendingBuyback, 1);

        vm.prank(owner);
        clock.advanceTime(1 days);
        vm.prank(owner);
        dust.harvest(0);

        assertEq(dust.pendingBuyback(), 0);
        assertEq(dust.dvrBoughtBack(), TWO_UNIT_DVR);
        assertEq(dust.lastHarvest().buybackSpent, 2);
    }

    function test_ZeroRewardHarvestDoesNotSpendDeferredBuyback() public {
        (CruiseControl dust, MockFarm low) = _dustFund();
        vm.prank(owner);
        clock.advanceTime(1 days);
        vm.prank(owner);
        dust.harvest(0);
        vm.prank(owner);
        dust.setStrategy(low);
        vm.prank(owner);
        clock.advanceTime(1 days);
        uint256 kBefore = _k();

        vm.prank(owner);
        dust.harvest(0);

        assertEq(dust.pendingBuyback(), 1);
        assertEq(dust.lastHarvest().rewards, 0);
        assertEq(dust.lastHarvest().buybackSpent, 0);
        assertEq(dust.dvrBoughtBack(), 0);
        assertEq(_k(), kBefore);
    }

    function test_ZeroRewardHarvestLeavesDeferredBuybackWhenTaxIsZero() public {
        (CruiseControl dust, MockFarm low) = _dustFund();
        vm.prank(owner);
        clock.advanceTime(1 days);
        vm.prank(owner);
        dust.harvest(0);
        MockFarm high = MockFarm(address(dust.activeFarm()));
        vm.prank(owner);
        pool.setTaxBps(0);
        vm.prank(owner);
        dust.setStrategy(low);
        vm.prank(owner);
        clock.advanceTime(1 days);
        uint256 supplyBefore = token.totalSupply();
        uint256 kBefore = _k();

        vm.recordLogs();
        vm.prank(owner);
        dust.harvest(0);

        assertFalse(_saw(IOfficialPool.Swapped.selector));
        assertEq(dust.pendingBuyback(), 1);
        assertEq(dust.dvrBoughtBack(), 0);
        assertEq(token.totalSupply(), supplyBefore);
        assertEq(_k(), kBefore);
        ITreasuryFund.Harvest memory skipped = dust.lastHarvest();
        assertEq(skipped.roundId, 1);
        assertEq(skipped.taxReleased, 0);
        assertEq(skipped.rewards, 0);
        assertEq(skipped.compounded, 0);
        assertEq(skipped.buybackSpent, 0);
        assertEq(skipped.dvrBurned, 0);
        assertEq(skipped.pendingBuyback, 1);

        vm.startPrank(owner);
        dust.setStrategy(high);
        clock.advanceTime(1 days);
        dust.harvest(0);
        vm.stopPrank();

        assertEq(dust.pendingBuyback(), 0);
        assertEq(dust.dvrBoughtBack(), 99_999_999_980_000);
        assertEq(dust.principal(), 732);
        ITreasuryFund.Harvest memory spent = dust.lastHarvest();
        assertEq(spent.roundId, 2);
        assertEq(spent.taxReleased, 0);
        assertEq(spent.rewards, 2);
        assertEq(spent.compounded, 1);
        assertEq(spent.buybackSpent, 2);
        assertEq(spent.dvrBurned, 99_999_999_980_000);
        assertEq(spent.pendingBuyback, 0);
    }

    function test_TinyPoolBuyIsDeferred() public {
        OfficialPool tiny = _tinyPool();
        MockFarm hot = new MockFarm(usdc, clock, 10_000, owner);
        RoundSchedule short = new RoundSchedule(clock, 1 days);
        CruiseControl dust = new CruiseControl(usdc, clock, short, splitter, tiny, SHARE_1, SHARE_2, _one(hot), owner);
        vm.startPrank(owner);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(dust));
        hot.addDepositor(address(dust));
        usdc.approve(address(hot), 1_000_000 * 10 ** 6);
        hot.fundRewards(1_000_000 * 10 ** 6);
        usdc.approve(address(dust), 73_000);
        dust.supply(73_000);
        dust.setStrategy(hot);
        dust.deposit(73_000);
        clock.advanceTime(1 days);
        dust.harvest(type(uint256).max);
        vm.stopPrank();

        assertEq(dust.pendingBuyback(), 100);
        assertEq(dust.dvrBoughtBack(), 0);
        assertEq(dust.lastHarvest().rewards, 200);
    }

    function test_DirectTransfersStayOutOfTheLedgers() public {
        vm.startPrank(owner);
        usdc.mint(address(fund), 7);
        token.mint(address(fund), 9);
        vm.stopPrank();
        _skip(30 days);
        vm.prank(owner);
        fund.harvest(0);

        assertEq(usdc.balanceOf(address(fund)), 7);
        assertEq(token.balanceOf(address(fund)), 9);
        assertEq(fund.idle(), 0);
        assertEq(fund.dvrBoughtBack(), DVR_OUT);
    }

    function test_QuoteRejectionRollsTheHarvestBack() public {
        TaxSplitter otherSplitter = new TaxSplitter(usdc, owner);
        RejectingPool rejecting = new RejectingPool(token, usdc, address(otherSplitter));
        vm.prank(owner);
        otherSplitter.setPool(address(rejecting));
        FixedFarm stub = new FixedFarm(usdc, clock);
        CruiseControl rejectingFund =
            new CruiseControl(usdc, clock, schedule, otherSplitter, rejecting, SHARE_1, SHARE_2, _one(stub), owner);
        stub.configure(rejectingFund, 2, false);
        vm.prank(owner);
        rejectingFund.setStrategy(stub);
        _skip(30 days);

        vm.prank(owner);
        vm.expectRevert(TreasuryFund.TreasuryFund__BuybackQuoteRejected.selector);
        rejectingFund.harvest(0);
        (bool harvested,) = rejectingFund.lastHarvestedRound();
        assertFalse(harvested);
    }

    function test_EmptyPoolQuoteRollsTheHarvestBack() public {
        TaxSplitter otherSplitter = new TaxSplitter(usdc, owner);
        OfficialPool empty = new OfficialPool(token, usdc, otherSplitter, owner, 100);
        vm.prank(owner);
        otherSplitter.setPool(address(empty));
        FixedFarm stub = new FixedFarm(usdc, clock);
        RoundSchedule otherSchedule = new RoundSchedule(clock, 30 days);
        CruiseControl emptyFund =
            new CruiseControl(usdc, clock, otherSchedule, otherSplitter, empty, SHARE_1, SHARE_2, _one(stub), owner);
        stub.configure(emptyFund, 2, false);
        vm.prank(owner);
        emptyFund.setStrategy(stub);
        _skip(30 days);

        vm.prank(owner);
        vm.expectRevert(IOfficialPool.OfficialPool__InsufficientReserves.selector);
        emptyFund.harvest(0);
    }

    function test_ReenteringFarmRevertsTheHarvest() public {
        FixedFarm stub = new FixedFarm(usdc, clock);
        CruiseControl reentering =
            new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, _one(stub), owner);
        stub.configure(reentering, 0, true);
        vm.prank(owner);
        reentering.setStrategy(stub);
        _skip(30 days);

        vm.prank(owner);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reentering.harvest(0);
    }

    function test_ReenteringPoolRevertsTheHarvest() public {
        TaxSplitter otherSplitter = new TaxSplitter(usdc, owner);
        ReenteringPool reentering = new ReenteringPool(token, usdc, address(otherSplitter));
        vm.prank(owner);
        otherSplitter.setPool(address(reentering));
        FixedFarm stub = new FixedFarm(usdc, clock);
        CruiseControl reenteringFund =
            new CruiseControl(usdc, clock, schedule, otherSplitter, reentering, SHARE_1, SHARE_2, _one(stub), owner);
        stub.configure(reenteringFund, 2, false);
        reentering.setFund(reenteringFund);
        vm.prank(owner);
        reenteringFund.setStrategy(stub);
        _skip(30 days);

        vm.prank(owner);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reenteringFund.harvest(0);
    }

    function test_SetBallotOnce() public {
        DegenDriver degen = _degen();
        MappedBallot ballot = new MappedBallot();

        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.BallotSet(address(ballot));
        vm.prank(owner);
        degen.setBallot(ballot);

        vm.prank(owner);
        vm.expectRevert(DegenDriver.DegenDriver__BallotAlreadySet.selector);
        degen.setBallot(ballot);

        vm.prank(owner);
        vm.expectRevert(DegenDriver.DegenDriver__ZeroAddress.selector);
        degen.setBallot(MappedBallot(address(0)));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        degen.setBallot(ballot);
    }

    function test_UnsetBallotLeavesIdleUndeposited() public {
        DegenDriver degen = _degenWithIdle();
        _skip(30 days);
        vm.prank(owner);
        degen.harvest(0);

        assertEq(address(degen.activeFarm()), address(0));
        assertEq(degen.idle(), 5_000 * 10 ** 6);
        assertEq(degen.dvrBoughtBack(), 0);
    }

    function test_ZeroWinnerKeepsTheCurrentFarm() public {
        DegenDriver degen = _degenWithIdle();
        MappedBallot ballot = new MappedBallot();
        vm.prank(owner);
        degen.setBallot(ballot);
        _skip(30 days);
        vm.prank(owner);
        degen.harvest(0);

        assertEq(address(degen.activeFarm()), address(0));
        assertEq(degen.idle(), 5_000 * 10 ** 6);
    }

    function test_ZeroWinnerKeepsTheActiveFarmAndDepositsTax() public {
        DegenDriver degen = _degenWithIdle();
        MockFarm highway = MockFarm(address(degen.strategyAt(0)));
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, highway);
        ballot.setWinner(1, IMockFarm(address(0)));
        vm.startPrank(owner);
        degen.setBallot(ballot);
        splitter.setRecipient(TaxSplitter.FundId.Fund2, address(degen));
        clock.advanceTime(30 days);
        degen.harvest(0);
        usdc.approve(address(pool), 100 * 10 ** 6);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100 * 10 ** 6, 0, block.timestamp);
        clock.advanceTime(30 days);
        vm.recordLogs();
        degen.harvest(0);
        vm.stopPrank();

        assertFalse(_saw(TreasuryFund.StrategySet.selector));
        assertEq(address(degen.activeFarm()), address(highway));
        assertEq(degen.idle(), 0);
        assertEq(degen.principal(), 5_082_591_781);
        assertEq(degen.dvrBoughtBack(), 3_957_233_299_941_386_903_042);
        ITreasuryFund.Harvest memory harvest_ = degen.lastHarvest();
        assertEq(harvest_.roundId, 1);
        assertEq(harvest_.taxReleased, 400_000);
        assertEq(harvest_.rewards, 164_383_561);
        assertEq(harvest_.compounded, 82_191_781);
        assertEq(harvest_.buybackSpent, 82_191_780);
        assertEq(harvest_.dvrBurned, 3_957_233_299_941_386_903_042);
        assertEq(harvest_.pendingBuyback, 0);
    }

    function test_FirstWinnerDepositsIdleAndTax() public {
        DegenDriver degen = _degenWithIdle();
        MockFarm highway = MockFarm(address(degen.strategyAt(0)));
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, highway);
        vm.startPrank(owner);
        degen.setBallot(ballot);
        usdc.approve(address(pool), 100 * 10 ** 6);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100 * 10 ** 6, 0, block.timestamp);
        splitter.setRecipient(TaxSplitter.FundId.Fund2, address(degen));
        clock.advanceTime(30 days);
        degen.harvest(0);
        vm.stopPrank();

        assertEq(address(degen.activeFarm()), address(highway));
        assertEq(degen.principal(), 5_000_400_000);
        assertEq(degen.idle(), 0);
        assertEq(degen.dvrBoughtBack(), 0);
    }

    function test_LaterSwitchIncludesAccruedRewards() public {
        DegenDriver degen = _degenWithIdle();
        MockFarm highway = MockFarm(address(degen.strategyAt(0)));
        MockFarm autobahn = MockFarm(address(degen.strategyAt(1)));
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, highway);
        ballot.setWinner(1, autobahn);
        vm.startPrank(owner);
        degen.setBallot(ballot);
        splitter.setRecipient(TaxSplitter.FundId.Fund2, address(degen));
        clock.advanceTime(30 days);
        degen.harvest(0);
        clock.advanceTime(30 days);
        vm.expectEmit(true, true, false, true, address(degen));
        emit TreasuryFund.StrategySet(address(highway), address(autobahn), 5_000 * 10 ** 6 + 82_191_781, 0);
        degen.harvest(0);
        vm.stopPrank();

        assertEq(address(degen.activeFarm()), address(autobahn));
        assertEq(degen.heldRewards(), 0);
        assertEq(degen.lastHarvest().rewards, 164_383_561);
        assertEq(degen.lastHarvest().compounded, 82_191_781);
        assertEq(degen.lastHarvest().buybackSpent, 82_191_780);
        assertEq(degen.dvrBoughtBack(), 4_035_655_030_707_175_139_647);
        assertEq(degen.principal(), 5_000 * 10 ** 6 + 82_191_781);
        assertEq(degen.lastHarvest().roundId, 1);
    }

    function test_CatchUpQueriesTheLatestClosedRound() public {
        DegenDriver degen = _degenWithIdle();
        MockFarm highway = MockFarm(address(degen.strategyAt(0)));
        MockFarm autobahn = MockFarm(address(degen.strategyAt(1)));
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, highway);
        ballot.setWinner(2, autobahn);
        vm.startPrank(owner);
        degen.setBallot(ballot);
        clock.advanceTime(30 days);
        degen.harvest(0);
        clock.advanceTime(60 days);
        degen.harvest(0);
        vm.stopPrank();

        assertEq(address(degen.activeFarm()), address(autobahn));
        assertEq(degen.lastHarvest().roundId, 2);
    }

    function test_SameWinnerDoesNotSwitch() public {
        DegenDriver degen = _degenWithIdle();
        MockFarm highway = MockFarm(address(degen.strategyAt(0)));
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, highway);
        ballot.setWinner(1, highway);
        vm.startPrank(owner);
        degen.setBallot(ballot);
        clock.advanceTime(30 days);
        degen.harvest(0);
        clock.advanceTime(30 days);
        degen.harvest(0);
        vm.stopPrank();

        assertEq(address(degen.activeFarm()), address(highway));
        assertEq(degen.lastHarvest().roundId, 1);
    }

    function test_UnlistedWinnerRollsTheHarvestBack() public {
        DegenDriver degen = _degenWithIdle();
        MockFarm outsider = new MockFarm(usdc, clock, APR, owner);
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, outsider);
        vm.prank(owner);
        degen.setBallot(ballot);
        _skip(30 days);
        uint256 idleBefore = degen.idle();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryFund.TreasuryFund__StrategyNotAllowed.selector, address(outsider))
        );
        degen.harvest(0);

        (bool ready, uint256 roundId) = degen.harvestableRound();
        assertTrue(ready);
        assertEq(roundId, 0);
        assertEq(degen.idle(), idleBefore);
        assertEq(address(degen.activeFarm()), address(0));
    }

    function test_RevertingWinnerRollsTheHarvestBack() public {
        DegenDriver degen = _degenWithIdle();
        RevertingBallot ballot = new RevertingBallot();
        vm.prank(owner);
        degen.setBallot(ballot);
        _skip(30 days);

        vm.prank(owner);
        vm.expectRevert(RevertingBallot.RevertingBallot__Rejected.selector);
        degen.harvest(0);
        (bool ready,) = degen.harvestableRound();
        assertTrue(ready);
    }

    function test_ChangedWinnerRollsTheHarvestBack() public {
        DegenDriver degen = _degenWithIdle();
        IdleBallot ballot =
            new IdleBallot(degen, 5_000 * 10 ** 6, IMockFarm(degen.strategyAt(0)), IMockFarm(degen.strategyAt(1)));
        vm.prank(owner);
        degen.setBallot(ballot);
        _skip(30 days);
        address first = address(degen.strategyAt(0));
        address second = address(degen.strategyAt(1));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DegenDriver.DegenDriver__WinnerChanged.selector, first, second));
        degen.harvest(0);
        (bool harvested,) = degen.lastHarvestedRound();
        assertFalse(harvested);
    }

    function _dustFund() private returns (CruiseControl dust, MockFarm low) {
        MockFarm high = new MockFarm(usdc, clock, 10_000, owner);
        low = new MockFarm(usdc, clock, 1, owner);
        IMockFarm[] memory farms = new IMockFarm[](2);
        farms[0] = high;
        farms[1] = low;
        RoundSchedule short = new RoundSchedule(clock, 1 days);
        dust = new CruiseControl(usdc, clock, short, splitter, pool, SHARE_1, SHARE_2, farms, owner);
        vm.startPrank(owner);
        high.addDepositor(address(dust));
        low.addDepositor(address(dust));
        usdc.approve(address(high), 1_000_000 * 10 ** 6);
        high.fundRewards(1_000_000 * 10 ** 6);
        usdc.approve(address(dust), 730);
        dust.supply(730);
        dust.setStrategy(high);
        dust.deposit(730);
        vm.stopPrank();
    }

    function _degen() private returns (DegenDriver degen) {
        MockFarm highway = new MockFarm(usdc, clock, 4_000, owner);
        MockFarm autobahn = new MockFarm(usdc, clock, 8_000, owner);
        MockFarm drift = new MockFarm(usdc, clock, 16_000, owner);
        IMockFarm[] memory cruiseFarms = new IMockFarm[](1);
        cruiseFarms[0] = highway;
        CruiseControl cruise =
            new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, cruiseFarms, owner);
        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = highway;
        farms[1] = autobahn;
        farms[2] = drift;
        degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, SHARE_1, SHARE_2, farms, owner);
        vm.startPrank(owner);
        highway.addDepositor(address(degen));
        autobahn.addDepositor(address(degen));
        drift.addDepositor(address(degen));
        usdc.approve(address(highway), 1_000_000 * 10 ** 6);
        highway.fundRewards(1_000_000 * 10 ** 6);
        usdc.approve(address(autobahn), 1_000_000 * 10 ** 6);
        autobahn.fundRewards(1_000_000 * 10 ** 6);
        vm.stopPrank();
    }

    function _degenWithIdle() private returns (DegenDriver degen) {
        degen = _degen();
        vm.startPrank(owner);
        usdc.approve(address(degen), 5_000 * 10 ** 6);
        degen.supply(5_000 * 10 ** 6);
        vm.stopPrank();
    }

    function _tinyPool() private returns (OfficialPool tiny) {
        TaxSplitter tinySplitter = new TaxSplitter(usdc, owner);
        tiny = new OfficialPool(token, usdc, tinySplitter, owner, 100);
        vm.startPrank(owner);
        tinySplitter.setPool(address(tiny));
        token.mint(owner, 1);
        usdc.mint(owner, 10_000 * 10 ** 6);
        token.approve(address(tiny), 1);
        usdc.approve(address(tiny), 10_000 * 10 ** 6);
        tiny.addLiquidity(1, 10_000 * 10 ** 6);
        vm.stopPrank();
        splitter = tinySplitter;
    }

    function _one(IMockFarm farm_) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm_;
    }

    function _skip(uint256 seconds_) private {
        vm.prank(owner);
        clock.advanceTime(seconds_);
    }

    function _k() private view returns (uint256 product) {
        product = pool.reserveDvr() * pool.reserveUsdc();
    }

    function _assertIdleRound() private view {
        (bool ready, uint256 roundId) = fund.harvestableRound();
        assertFalse(ready);
        assertEq(roundId, 0);
        (bool harvested, uint256 harvestedRound) = fund.lastHarvestedRound();
        assertFalse(harvested);
        assertEq(harvestedRound, 0);
        assertEq(fund.pendingBuyback(), 0);
        assertEq(fund.dvrBoughtBack(), 0);
        ITreasuryFund.Harvest memory harvest_ = fund.lastHarvest();
        assertEq(harvest_.roundId, 0);
        assertEq(harvest_.taxReleased, 0);
        assertEq(harvest_.rewards, 0);
        assertEq(harvest_.compounded, 0);
        assertEq(harvest_.buybackSpent, 0);
        assertEq(harvest_.dvrBurned, 0);
        assertEq(harvest_.pendingBuyback, 0);
    }

    function _assertHarvest(
        uint256 harvestedRound,
        bool harvested,
        uint256 roundId,
        uint256 taxReleased,
        uint256 rewards,
        uint256 compounded,
        uint256 buybackSpent,
        uint256 dvrBurned,
        uint256 pending
    ) private view {
        (bool wasHarvested, uint256 stored) = fund.lastHarvestedRound();
        assertEq(wasHarvested, harvested);
        assertEq(stored, harvestedRound);
        ITreasuryFund.Harvest memory harvest_ = fund.lastHarvest();
        assertEq(harvest_.roundId, roundId);
        assertEq(harvest_.taxReleased, taxReleased);
        assertEq(harvest_.rewards, rewards);
        assertEq(harvest_.compounded, compounded);
        assertEq(harvest_.buybackSpent, buybackSpent);
        assertEq(harvest_.dvrBurned, dvrBurned);
        assertEq(harvest_.pendingBuyback, pending);
    }

    function _assertHarvestRound(uint256 roundId) private view {
        (bool harvested, uint256 stored) = fund.lastHarvestedRound();
        assertTrue(harvested);
        assertEq(stored, roundId);
        assertEq(fund.lastHarvest().roundId, roundId);
    }

    function _assertFundRound(CruiseControl productionFund, uint256 roundId) private view {
        (bool harvested, uint256 stored) = productionFund.lastHarvestedRound();
        assertTrue(harvested);
        assertEq(stored, roundId);
    }

    function _saw(bytes32 topic) private view returns (bool saw_) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count = logs.length;
        for (uint256 i = 0; i < count; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return true;
            }
        }
        saw_ = false;
    }
}
