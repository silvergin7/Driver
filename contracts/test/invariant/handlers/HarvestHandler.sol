// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMockFarm} from "../../../src/interfaces/IMockFarm.sol";
import {IOfficialPool} from "../../../src/interfaces/IOfficialPool.sol";
import {CruiseControl} from "../../../src/CruiseControl.sol";
import {DegenDriver} from "../../../src/DegenDriver.sol";
import {DemoDriverClock} from "../../../src/DemoDriverClock.sol";
import {DriverClock} from "../../../src/DriverClock.sol";
import {DriverToken} from "../../../src/DriverToken.sol";
import {MockFarm} from "../../../src/MockFarm.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";
import {OfficialPool} from "../../../src/OfficialPool.sol";
import {RoundSchedule} from "../../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../../src/TreasuryFund.sol";
import {MappedBallot} from "../../mocks/HarvestMocks.sol";

contract HarvestHandler is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant EPOCH = 30 days;
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;
    uint256 internal constant FRESH_DVR = 100 * 10 ** 18;
    uint256 internal constant POSITION = 10_000 * 10 ** 6;
    uint256 internal constant APR = 500;

    MockUSDC public s_usdc;
    DriverToken public s_token;
    DemoDriverClock public s_clock;
    OfficialPool public s_pool;
    CruiseControl public s_fund;
    DegenDriver public s_openFund;

    uint256 public s_ghostIdle;
    uint256 public s_ghostPrincipal;
    uint256 public s_ghostHeld;
    uint256 public s_ghostPending;
    uint256 public s_ghostDonatedUsdc;
    uint256 public s_ghostDonatedDvr;
    uint256 public s_ghostBought;
    uint256 public s_ghostMinted;
    uint256 public s_ghostTax;
    uint256 public s_ghostOpenTax;
    uint256 public s_ghostOpenIdle;
    uint256 public s_reserveDvr;
    uint256 public s_reserveUsdc;
    uint256 public s_farmReserve;
    uint256 public s_kBefore;
    uint256 public s_kAfter;
    uint256 public s_lastRound;
    bool public s_roundKnown;

    uint256 public s_across;
    uint256 public s_warps;
    uint256 public s_again;
    uint256 public s_zeroRewards;
    uint256 public s_dust;
    uint256 public s_slippage;
    uint256 public s_noFarm;
    uint256 public s_winners;
    uint256 public s_zeroWinners;
    uint256 public s_refills;
    uint256 public s_unauthorized;
    uint256 public s_usdcDonations;
    uint256 public s_dvrDonations;
    uint256 public s_fullPays;
    uint256 public s_cappedPays;

    address internal s_owner = makeAddr("harvestOwner");
    MockFarm internal s_farm;
    RoundSchedule internal s_schedule;
    TaxSplitter internal s_splitter;
    bool internal s_active;
    uint256 internal s_checkpoint;

    error HarvestHandler__KDecreased(uint256 beforeK, uint256 afterK);
    error HarvestHandler__ReserveMismatch(uint256 dvr, uint256 usdc);
    error HarvestHandler__BoughtMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__PendingMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__IdleMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__PrincipalMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__RoundMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__BurnMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__BalanceMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__ValueMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__DvrBalanceMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__MintMismatch(uint256 actual, uint256 expected);
    error HarvestHandler__BuybackWasZero();
    error HarvestHandler__ExpectedFullPay();
    error HarvestHandler__SlippageMismatch();
    error HarvestHandler__UnauthorizedSucceeded();
    error HarvestHandler__UnauthorizedMismatch();
    error HarvestHandler__DustMismatch();
    error HarvestHandler__WinnerMismatch();
    error HarvestHandler__HeldMismatch(uint256 actual, uint256 expected);

    constructor() {
        s_usdc = new MockUSDC(s_owner);
        s_token = new DriverToken(s_owner);
        s_clock = new DemoDriverClock(s_owner);
        s_splitter = new TaxSplitter(s_usdc, s_owner);
        s_pool = new OfficialPool(s_token, s_usdc, s_splitter, s_owner, 100);
        s_schedule = new RoundSchedule(s_clock, EPOCH);
        vm.prank(s_owner);
        s_splitter.setPool(address(s_pool));
        s_farm = new MockFarm(s_usdc, s_clock, APR, s_owner);
        s_fund =
            new CruiseControl(s_usdc, s_clock, s_schedule, s_splitter, s_pool, SHARE_1, SHARE_2, _one(s_farm), s_owner);

        vm.startPrank(s_owner);
        s_token.mint(s_owner, SEED_DVR);
        s_usdc.mint(s_owner, 1_000_000_000_000_000 * 10 ** 6);
        s_token.approve(address(s_pool), SEED_DVR);
        s_usdc.approve(address(s_pool), SEED_USDC);
        s_pool.addLiquidity(SEED_DVR, SEED_USDC);
        s_usdc.approve(address(s_farm), type(uint256).max);
        s_farm.fundRewards(10_000_000 * 10 ** 6);
        s_farm.addDepositor(address(s_fund));
        s_splitter.setRecipient(TaxSplitter.FundId.Fund1, address(s_fund));
        vm.stopPrank();

        s_ghostMinted = SEED_DVR;
        s_reserveDvr = SEED_DVR;
        s_reserveUsdc = SEED_USDC;
        s_farmReserve = 10_000_000 * 10 ** 6;
        s_kBefore = SEED_DVR * SEED_USDC;
        s_kAfter = s_kBefore;
        s_checkpoint = s_clock.currentTime();

        s_openFund = _openFund();
        vm.prank(s_owner);
        s_splitter.setRecipient(TaxSplitter.FundId.Fund2, address(s_openFund));
        s_ghostOpenIdle = 5_000 * 10 ** 6;
    }

    function harvestAcrossClosedRounds() external tracksMain {
        _ensurePosition(POSITION);
        _topUp(3 * EPOCH);
        _advance(3 * EPOCH);
        uint256 beforeBought = s_ghostBought;
        _harvestMain(true);
        if (s_ghostBought == beforeBought) {
            revert HarvestHandler__BuybackWasZero();
        }
        s_across += 1;
    }

    function harvestByWarp() external tracksMain {
        DriverClock production = new DriverClock();
        (TaxSplitter splitter_, OfficialPool pool_) = _freshPool();
        MockFarm farm_ = new MockFarm(s_usdc, production, APR, s_owner);
        RoundSchedule schedule_ = new RoundSchedule(production, EPOCH);
        CruiseControl fund_ =
            new CruiseControl(s_usdc, production, schedule_, splitter_, pool_, SHARE_1, SHARE_2, _one(farm_), s_owner);
        vm.startPrank(s_owner);
        farm_.addDepositor(address(fund_));
        s_usdc.approve(address(farm_), type(uint256).max);
        farm_.fundRewards(10_000_000 * 10 ** 6);
        s_usdc.approve(address(fund_), POSITION);
        fund_.supply(POSITION);
        fund_.setStrategy(farm_);
        fund_.deposit(POSITION);
        splitter_.setRecipient(TaxSplitter.FundId.Fund1, address(fund_));
        vm.stopPrank();

        uint256 reserveDvr = FRESH_DVR;
        uint256 reserveUsdc = SEED_USDC;
        uint256 kBefore = reserveDvr * reserveUsdc;
        vm.warp(block.timestamp + EPOCH);
        uint256 rewards = _earned(POSITION, APR, EPOCH);
        uint256 burned = _finishFresh(fund_, 10_000_000 * 10 ** 6, rewards, reserveDvr, reserveUsdc, true);
        if (burned == 0) {
            revert HarvestHandler__BuybackWasZero();
        }
        _requireK(pool_, kBefore);
        (bool harvested, uint256 roundId) = fund_.lastHarvestedRound();
        if (!harvested || roundId != 0) {
            revert HarvestHandler__RoundMismatch(roundId, 0);
        }
        s_warps += 1;
    }

    function harvestAgain() external tracksMain {
        _ensurePosition(POSITION);
        uint256 beforeBought = s_ghostBought;
        _topUp(EPOCH);
        _advance(EPOCH);
        _harvestMain(true);
        uint256 mid = s_ghostBought;
        _topUp(EPOCH);
        _advance(EPOCH);
        _harvestMain(true);
        if (mid == beforeBought || s_ghostBought == mid) {
            revert HarvestHandler__BuybackWasZero();
        }
        s_again += 1;
    }

    function harvestZeroRewards() external tracksMain {
        (TaxSplitter splitter_, OfficialPool pool_) = _freshPool();
        MockFarm farm_ = new MockFarm(s_usdc, s_clock, APR, s_owner);
        RoundSchedule schedule_ = new RoundSchedule(s_clock, EPOCH);
        CruiseControl fund_ =
            new CruiseControl(s_usdc, s_clock, schedule_, splitter_, pool_, SHARE_1, SHARE_2, _one(farm_), s_owner);
        vm.startPrank(s_owner);
        farm_.addDepositor(address(fund_));
        fund_.setStrategy(farm_);
        splitter_.setRecipient(TaxSplitter.FundId.Fund1, address(fund_));
        vm.stopPrank();
        _advance(EPOCH);
        uint256 kBefore = FRESH_DVR * SEED_USDC;
        vm.prank(s_owner);
        fund_.harvest(0);
        if (fund_.lastHarvest().rewards != 0 || fund_.dvrBoughtBack() != 0 || fund_.pendingBuyback() != 0) {
            revert HarvestHandler__BurnMismatch(fund_.dvrBoughtBack(), 0);
        }
        _requireK(pool_, kBefore);
        s_zeroRewards += 1;
    }

    function harvestDust() external tracksMain {
        (TaxSplitter splitter_, OfficialPool pool_) = _freshPool();
        MockFarm farm_ = new MockFarm(s_usdc, s_clock, 10_000, s_owner);
        RoundSchedule schedule_ = new RoundSchedule(s_clock, 1 days);
        CruiseControl fund_ =
            new CruiseControl(s_usdc, s_clock, schedule_, splitter_, pool_, SHARE_1, SHARE_2, _one(farm_), s_owner);
        vm.startPrank(s_owner);
        farm_.addDepositor(address(fund_));
        s_usdc.approve(address(farm_), type(uint256).max);
        farm_.fundRewards(1_000 * 10 ** 6);
        s_usdc.approve(address(fund_), 730);
        fund_.supply(730);
        fund_.setStrategy(farm_);
        fund_.deposit(730);
        splitter_.setRecipient(TaxSplitter.FundId.Fund1, address(fund_));
        s_clock.advanceTime(1 days);
        fund_.harvest(type(uint256).max);
        vm.stopPrank();
        if (fund_.pendingBuyback() != 1 || fund_.dvrBoughtBack() != 0 || fund_.lastHarvest().rewards != 2) {
            revert HarvestHandler__DustMismatch();
        }
        _countPay(2, 2);
        s_dust += 1;
    }

    function harvestSlippage() external tracksMain {
        (TaxSplitter splitter_, OfficialPool pool_) = _freshPool();
        MockFarm farm_ = new MockFarm(s_usdc, s_clock, APR, s_owner);
        RoundSchedule schedule_ = new RoundSchedule(s_clock, EPOCH);
        CruiseControl fund_ =
            new CruiseControl(s_usdc, s_clock, schedule_, splitter_, pool_, SHARE_1, SHARE_2, _one(farm_), s_owner);
        vm.startPrank(s_owner);
        farm_.addDepositor(address(fund_));
        s_usdc.approve(address(farm_), type(uint256).max);
        farm_.fundRewards(10_000_000 * 10 ** 6);
        s_usdc.approve(address(fund_), POSITION);
        fund_.supply(POSITION);
        fund_.setStrategy(farm_);
        fund_.deposit(POSITION);
        splitter_.setRecipient(TaxSplitter.FundId.Fund1, address(fund_));
        vm.stopPrank();
        _advance(EPOCH);
        uint256 rewards = _earned(POSITION, APR, EPOCH);
        uint256 half = rewards / 2;
        (uint256 dvrOut, bool deferred) = _quote(FRESH_DVR, SEED_USDC, half);
        if (deferred || dvrOut == 0) {
            revert HarvestHandler__BuybackWasZero();
        }
        uint256 kBefore = FRESH_DVR * SEED_USDC;
        vm.prank(s_owner);
        try fund_.harvest(dvrOut + 1) {
            revert HarvestHandler__SlippageMismatch();
        } catch (bytes memory reason) {
            bytes32 expected = keccak256(
                abi.encodeWithSelector(IOfficialPool.OfficialPool__InsufficientOutput.selector, dvrOut, dvrOut + 1)
            );
            if (keccak256(reason) != expected) {
                revert HarvestHandler__SlippageMismatch();
            }
        }
        _requireK(pool_, kBefore);
        (bool harvested,) = fund_.lastHarvestedRound();
        if (harvested) {
            revert HarvestHandler__RoundMismatch(1, 0);
        }
        s_slippage += 1;
    }

    function harvestWithNoFarm() external tracksMain {
        _advance(EPOCH);
        if (s_ghostOpenTax == 0) {
            _sharedBuy(100 * 10 ** 6);
        }
        uint256 tax = s_ghostOpenTax;
        s_ghostOpenTax = 0;
        s_ghostOpenIdle += tax;
        uint256 roundId = s_schedule.latestClosedRound();
        uint256 kBefore = s_reserveDvr * s_reserveUsdc;
        vm.prank(s_owner);
        s_openFund.harvest(0);
        if (s_openFund.idle() != s_ghostOpenIdle || address(s_openFund.activeFarm()) != address(0)) {
            revert HarvestHandler__IdleMismatch(s_openFund.idle(), s_ghostOpenIdle);
        }
        (bool harvested, uint256 stored) = s_openFund.lastHarvestedRound();
        if (!harvested || stored != roundId) {
            revert HarvestHandler__RoundMismatch(stored, roundId);
        }
        _requireProduct(kBefore);
        s_noFarm += 1;
    }

    function harvestWithWinner() external tracksMain {
        (TaxSplitter splitter_, OfficialPool pool_) = _freshPool();
        MockFarm highway = new MockFarm(s_usdc, s_clock, 4_000, s_owner);
        MockFarm autobahn = new MockFarm(s_usdc, s_clock, 8_000, s_owner);
        IMockFarm[] memory farms = new IMockFarm[](2);
        farms[0] = highway;
        farms[1] = autobahn;
        RoundSchedule schedule_ = new RoundSchedule(s_clock, EPOCH);
        DegenDriver fund_ =
            new DegenDriver(s_usdc, s_clock, schedule_, splitter_, pool_, SHARE_1, SHARE_2, farms, s_owner);
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, highway);
        ballot.setWinner(1, autobahn);
        vm.startPrank(s_owner);
        highway.addDepositor(address(fund_));
        autobahn.addDepositor(address(fund_));
        s_usdc.approve(address(highway), type(uint256).max);
        s_usdc.approve(address(autobahn), type(uint256).max);
        highway.fundRewards(10_000_000 * 10 ** 6);
        autobahn.fundRewards(10_000_000 * 10 ** 6);
        s_usdc.approve(address(fund_), 5_000 * 10 ** 6);
        fund_.supply(5_000 * 10 ** 6);
        fund_.setBallot(ballot);
        splitter_.setRecipient(TaxSplitter.FundId.Fund2, address(fund_));
        s_usdc.approve(address(pool_), 100 * 10 ** 6);
        pool_.swapExactInput(IOfficialPool.Direction.Buy, 100 * 10 ** 6, 0, block.timestamp);
        s_clock.advanceTime(EPOCH);
        fund_.harvest(0);
        vm.stopPrank();
        if (
            fund_.principal() != 5_000_400_000 || fund_.dvrBoughtBack() != 0
                || address(fund_.activeFarm()) != address(highway)
        ) {
            revert HarvestHandler__WinnerMismatch();
        }

        vm.startPrank(s_owner);
        s_clock.advanceTime(EPOCH);
        fund_.harvest(0);
        vm.stopPrank();
        uint256 rewards = _earned(5_000_400_000, 4_000, EPOCH);
        if (
            address(fund_.activeFarm()) != address(autobahn) || fund_.heldRewards() != 0
                || fund_.lastHarvest().rewards != rewards || fund_.lastHarvest().roundId != 1
        ) {
            revert HarvestHandler__WinnerMismatch();
        }
        _countPay(rewards, rewards);

        ballot.setWinner(2, IMockFarm(address(0)));
        uint256 keptPrincipal = fund_.principal();
        uint256 keptTax = Math.mulDiv(Math.mulDiv(rewards / 2, 100, BPS, Math.Rounding.Ceil), 4_000, BPS);
        vm.startPrank(s_owner);
        s_clock.advanceTime(EPOCH);
        fund_.harvest(0);
        vm.stopPrank();
        uint256 keptRewards = _earned(keptPrincipal, 8_000, EPOCH);
        if (
            address(fund_.activeFarm()) != address(autobahn) || fund_.lastHarvest().roundId != 2
                || fund_.lastHarvest().taxReleased != keptTax
                || fund_.principal() != keptPrincipal + (keptRewards - keptRewards / 2) + keptTax
        ) {
            revert HarvestHandler__WinnerMismatch();
        }
        s_zeroWinners += 1;

        CruiseControl parked = _parkedRewards(splitter_, pool_);
        if (parked.heldRewards() != 0) {
            revert HarvestHandler__HeldMismatch(parked.lastHarvest().rewards, 0);
        }
        s_winners += 1;
    }

    function refillReserve(uint256 amount) external tracksMain {
        amount = bound(amount, 1, 1_000_000 * 10 ** 6);
        vm.startPrank(s_owner);
        s_usdc.approve(address(s_farm), amount);
        s_farm.fundRewards(amount);
        vm.stopPrank();
        s_farmReserve += amount;

        (TaxSplitter splitter_, OfficialPool pool_) = _freshPool();
        MockFarm farm_ = new MockFarm(s_usdc, s_clock, APR, s_owner);
        RoundSchedule schedule_ = new RoundSchedule(s_clock, EPOCH);
        CruiseControl fund_ =
            new CruiseControl(s_usdc, s_clock, schedule_, splitter_, pool_, SHARE_1, SHARE_2, _one(farm_), s_owner);
        uint256 principal = 1_000_000 * 10 ** 6;
        vm.startPrank(s_owner);
        farm_.addDepositor(address(fund_));
        s_usdc.approve(address(farm_), principal + 100);
        farm_.fundRewards(100);
        s_usdc.approve(address(fund_), principal);
        fund_.supply(principal);
        fund_.setStrategy(farm_);
        fund_.deposit(principal);
        splitter_.setRecipient(TaxSplitter.FundId.Fund1, address(fund_));
        vm.stopPrank();
        _advance(EPOCH);
        uint256 owed = _earned(principal, APR, EPOCH);
        _finishFresh(fund_, 100, owed, FRESH_DVR, SEED_USDC, false);
        if (owed <= 100 || fund_.lastHarvest().rewards != 100) {
            revert HarvestHandler__ExpectedFullPay();
        }
        s_refills += 1;
    }

    function unauthorizedHarvest() external tracksMain {
        vm.prank(makeAddr("harvestStranger"));
        try s_fund.harvest(0) {
            revert HarvestHandler__UnauthorizedSucceeded();
        } catch (bytes memory reason) {
            bytes32 expected = keccak256(
                abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("harvestStranger"))
            );
            if (keccak256(reason) != expected) {
                revert HarvestHandler__UnauthorizedMismatch();
            }
        }
        s_unauthorized += 1;
    }

    function donateUsdc(uint256 amount) external tracksMain {
        amount = bound(amount, 1, 1_000_000 * 10 ** 6);
        vm.prank(s_owner);
        s_usdc.mint(address(s_fund), amount);
        s_ghostDonatedUsdc += amount;
        s_usdcDonations += 1;
    }

    function donateDvr(uint256 amount) external tracksMain {
        amount = bound(amount, 1, 100 * 10 ** 18);
        vm.prank(s_owner);
        s_token.mint(address(s_fund), amount);
        s_ghostMinted += amount;
        s_ghostDonatedDvr += amount;
        s_dvrDonations += 1;
    }

    function _ensurePosition(uint256 amount) private {
        if (!s_active) {
            vm.prank(s_owner);
            s_fund.setStrategy(s_farm);
            s_active = true;
            s_checkpoint = s_clock.currentTime();
        }
        if (s_ghostPrincipal == 0) {
            vm.startPrank(s_owner);
            s_usdc.approve(address(s_fund), amount);
            s_fund.supply(amount);
            s_fund.deposit(amount);
            vm.stopPrank();
            s_ghostIdle = 0;
            s_ghostPrincipal = amount;
            s_checkpoint = s_clock.currentTime();
        }
    }

    function _topUp(uint256 elapsed) private {
        uint256 owed = _earned(s_ghostPrincipal, APR, (s_clock.currentTime() + elapsed) - s_checkpoint);
        if (owed + 1 > s_farmReserve) {
            uint256 extra = owed + 1 - s_farmReserve;
            vm.startPrank(s_owner);
            s_usdc.approve(address(s_farm), extra);
            s_farm.fundRewards(extra);
            vm.stopPrank();
            s_farmReserve += extra;
        }
    }

    function _advance(uint256 seconds_) private {
        vm.prank(s_owner);
        s_clock.advanceTime(seconds_);
    }

    function _harvestMain(bool requireFull) private {
        uint256 roundId = s_schedule.latestClosedRound();
        uint256 kBefore = s_reserveDvr * s_reserveUsdc;
        uint256 elapsed = s_clock.currentTime() - s_checkpoint;
        uint256 owed = _earned(s_ghostPrincipal, APR, elapsed);
        uint256 paid = owed > s_farmReserve ? s_farmReserve : owed;
        if (requireFull && paid != owed) {
            revert HarvestHandler__ExpectedFullPay();
        }
        _countPay(owed, paid);
        uint256 rewards = s_ghostHeld + paid;
        uint256 half = rewards / 2;
        uint256 compound = rewards - half;
        uint256 tax = s_ghostTax;
        s_ghostTax = 0;
        s_ghostHeld = 0;
        s_farmReserve -= paid;
        s_checkpoint = s_clock.currentTime();
        s_ghostPrincipal += compound + s_ghostIdle + tax;
        s_ghostIdle = 0;

        uint256 burned;
        uint256 spent;
        if (half != 0) {
            uint256 spend = half + s_ghostPending;
            (uint256 dvrOut, bool deferred) = _quote(s_reserveDvr, s_reserveUsdc, spend);
            if (deferred) {
                s_ghostPending = spend;
            } else {
                uint256 usdcTax = Math.mulDiv(spend, 100, BPS, Math.Rounding.Ceil);
                s_ghostPending = 0;
                burned = dvrOut;
                spent = spend;
                s_ghostBought += dvrOut;
                _takeBuy(spend, dvrOut, usdcTax);
            }
        }

        vm.prank(s_owner);
        s_fund.harvest(0);
        s_lastRound = roundId;
        s_roundKnown = true;
        s_kBefore = kBefore;
        s_kAfter = s_reserveDvr * s_reserveUsdc;
        if (s_pool.reserveDvr() * s_pool.reserveUsdc() < kBefore) {
            revert HarvestHandler__KDecreased(kBefore, s_pool.reserveDvr() * s_pool.reserveUsdc());
        }
        if (s_pool.reserveDvr() != s_reserveDvr || s_pool.reserveUsdc() != s_reserveUsdc) {
            revert HarvestHandler__ReserveMismatch(s_pool.reserveDvr(), s_pool.reserveUsdc());
        }
        if (s_fund.dvrBoughtBack() != s_ghostBought) {
            revert HarvestHandler__BoughtMismatch(s_fund.dvrBoughtBack(), s_ghostBought);
        }
        if (s_fund.lastHarvest().dvrBurned != burned || s_fund.lastHarvest().buybackSpent != spent) {
            revert HarvestHandler__BurnMismatch(s_fund.lastHarvest().dvrBurned, burned);
        }
        if (s_fund.lastHarvest().roundId != roundId) {
            revert HarvestHandler__RoundMismatch(s_fund.lastHarvest().roundId, roundId);
        }
    }

    function _finishFresh(
        CruiseControl fund_,
        uint256 reserve,
        uint256 owed,
        uint256 reserveDvr,
        uint256 reserveUsdc,
        bool requireFull
    ) private returns (uint256 burned) {
        uint256 paid = owed > reserve ? reserve : owed;
        if (requireFull && paid != owed) {
            revert HarvestHandler__ExpectedFullPay();
        }
        _countPay(owed, paid);
        uint256 half = paid / 2;
        (uint256 dvrOut, bool deferred) = _quote(reserveDvr, reserveUsdc, half);
        vm.prank(s_owner);
        fund_.harvest(0);
        if (deferred || half == 0) {
            if (fund_.dvrBoughtBack() != 0 || fund_.pendingBuyback() != (half == 0 ? 0 : half)) {
                revert HarvestHandler__PendingMismatch(fund_.pendingBuyback(), half);
            }
            return 0;
        }
        if (fund_.dvrBoughtBack() != dvrOut) {
            revert HarvestHandler__BoughtMismatch(fund_.dvrBoughtBack(), dvrOut);
        }
        burned = dvrOut;
    }

    function _parkedRewards(TaxSplitter splitter_, OfficialPool pool_) private returns (CruiseControl parked) {
        MockFarm first = new MockFarm(s_usdc, s_clock, APR, s_owner);
        MockFarm second = new MockFarm(s_usdc, s_clock, APR, s_owner);
        IMockFarm[] memory farms = new IMockFarm[](2);
        farms[0] = first;
        farms[1] = second;
        RoundSchedule schedule_ = new RoundSchedule(s_clock, EPOCH);
        parked = new CruiseControl(s_usdc, s_clock, schedule_, splitter_, pool_, SHARE_1, SHARE_2, farms, s_owner);
        vm.startPrank(s_owner);
        first.addDepositor(address(parked));
        second.addDepositor(address(parked));
        s_usdc.approve(address(first), type(uint256).max);
        s_usdc.approve(address(second), type(uint256).max);
        first.fundRewards(10_000_000 * 10 ** 6);
        second.fundRewards(10_000_000 * 10 ** 6);
        s_usdc.approve(address(parked), POSITION);
        parked.supply(POSITION);
        parked.setStrategy(first);
        parked.deposit(POSITION);
        splitter_.setRecipient(TaxSplitter.FundId.Fund1, address(parked));
        s_clock.advanceTime(EPOCH);
        parked.setStrategy(second);
        uint256 held = parked.heldRewards();
        uint256 expected = _earned(POSITION, APR, EPOCH);
        if (held != expected) {
            revert HarvestHandler__HeldMismatch(held, expected);
        }
        s_clock.advanceTime(EPOCH);
        parked.harvest(0);
        vm.stopPrank();
        uint256 secondEarned = _earned(POSITION, APR, EPOCH);
        if (parked.lastHarvest().rewards != held + secondEarned || parked.heldRewards() != 0) {
            revert HarvestHandler__HeldMismatch(parked.lastHarvest().rewards, held + secondEarned);
        }
    }

    function _sharedBuy(uint256 amountIn) private {
        (uint256 dvrOut, bool deferred) = _quote(s_reserveDvr, s_reserveUsdc, amountIn);
        if (deferred) {
            revert HarvestHandler__BuybackWasZero();
        }
        uint256 usdcTax = Math.mulDiv(amountIn, 100, BPS, Math.Rounding.Ceil);
        uint256 kBefore = s_reserveDvr * s_reserveUsdc;
        vm.startPrank(s_owner);
        s_usdc.approve(address(s_pool), amountIn);
        s_pool.swapExactInput(IOfficialPool.Direction.Buy, amountIn, dvrOut, block.timestamp);
        vm.stopPrank();
        _takeBuy(amountIn, dvrOut, usdcTax);
        if (s_pool.reserveDvr() * s_pool.reserveUsdc() < kBefore) {
            revert HarvestHandler__KDecreased(kBefore, s_pool.reserveDvr() * s_pool.reserveUsdc());
        }
    }

    function _takeBuy(uint256 amountIn, uint256 dvrOut, uint256 usdcTax) private {
        uint256 toCurve = amountIn - usdcTax;
        s_reserveDvr -= dvrOut;
        s_reserveUsdc += toCurve;
        uint256 fund1 = Math.mulDiv(usdcTax, 4_000, BPS);
        uint256 fund2 = Math.mulDiv(usdcTax, 4_000, BPS);
        s_ghostTax += fund1;
        s_ghostOpenTax += fund2;
    }

    function _freshPool() private returns (TaxSplitter splitter_, OfficialPool pool_) {
        splitter_ = new TaxSplitter(s_usdc, s_owner);
        pool_ = new OfficialPool(s_token, s_usdc, splitter_, s_owner, 100);
        vm.startPrank(s_owner);
        splitter_.setPool(address(pool_));
        s_token.mint(s_owner, FRESH_DVR);
        s_usdc.mint(s_owner, SEED_USDC);
        s_token.approve(address(pool_), FRESH_DVR);
        s_usdc.approve(address(pool_), SEED_USDC);
        pool_.addLiquidity(FRESH_DVR, SEED_USDC);
        vm.stopPrank();
        s_ghostMinted += FRESH_DVR;
    }

    function _openFund() private returns (DegenDriver fund_) {
        MockFarm highway = new MockFarm(s_usdc, s_clock, 4_000, s_owner);
        MockFarm autobahn = new MockFarm(s_usdc, s_clock, 8_000, s_owner);
        MockFarm drift = new MockFarm(s_usdc, s_clock, 16_000, s_owner);
        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = highway;
        farms[1] = autobahn;
        farms[2] = drift;
        fund_ = new DegenDriver(s_usdc, s_clock, s_schedule, s_splitter, s_pool, SHARE_1, SHARE_2, farms, s_owner);
        vm.startPrank(s_owner);
        s_usdc.approve(address(fund_), 5_000 * 10 ** 6);
        fund_.supply(5_000 * 10 ** 6);
        vm.stopPrank();
    }

    function _quote(uint256 reserveDvr, uint256 reserveUsdc, uint256 amountIn)
        private
        pure
        returns (uint256 dvrOut, bool deferred)
    {
        if (amountIn == 0) {
            return (0, true);
        }
        uint256 usdcTax = Math.mulDiv(amountIn, 100, BPS, Math.Rounding.Ceil);
        uint256 toCurve = amountIn - usdcTax;
        if (toCurve == 0) {
            return (0, true);
        }
        dvrOut = Math.mulDiv(reserveDvr, toCurve, reserveUsdc + toCurve);
        if (dvrOut == 0 || dvrOut >= reserveDvr) {
            return (0, true);
        }
        deferred = false;
    }

    function _earned(uint256 principal, uint256 apr, uint256 elapsed) private pure returns (uint256 rewards) {
        if (principal == 0 || elapsed == 0) {
            return 0;
        }
        rewards = Math.mulDiv(principal, apr * elapsed, BPS * YEAR);
    }

    function _countPay(uint256 owed, uint256 paid) private {
        if (owed == 0) {
            return;
        }
        if (paid == owed) {
            s_fullPays += 1;
        } else {
            s_cappedPays += 1;
        }
    }

    function _requireK(OfficialPool pool_, uint256 beforeK) private view {
        uint256 afterK = pool_.reserveDvr() * pool_.reserveUsdc();
        if (afterK < beforeK) {
            revert HarvestHandler__KDecreased(beforeK, afterK);
        }
    }

    function _requireProduct(uint256 beforeK) private view {
        uint256 afterK = s_pool.reserveDvr() * s_pool.reserveUsdc();
        if (afterK < beforeK) {
            revert HarvestHandler__KDecreased(beforeK, afterK);
        }
    }

    function _checkMain() private view {
        if (s_fund.idle() != s_ghostIdle) {
            revert HarvestHandler__IdleMismatch(s_fund.idle(), s_ghostIdle);
        }
        if (s_fund.principal() != s_ghostPrincipal) {
            revert HarvestHandler__PrincipalMismatch(s_fund.principal(), s_ghostPrincipal);
        }
        if (s_fund.pendingBuyback() != s_ghostPending) {
            revert HarvestHandler__PendingMismatch(s_fund.pendingBuyback(), s_ghostPending);
        }
        if (s_fund.dvrBoughtBack() != s_ghostBought) {
            revert HarvestHandler__BoughtMismatch(s_fund.dvrBoughtBack(), s_ghostBought);
        }
        if (s_fund.value() != s_ghostIdle + s_ghostPrincipal) {
            revert HarvestHandler__ValueMismatch(s_fund.value(), s_ghostIdle + s_ghostPrincipal);
        }
        uint256 expectedBalance = s_ghostIdle + s_ghostHeld + s_ghostPending + s_ghostDonatedUsdc;
        if (s_usdc.balanceOf(address(s_fund)) != expectedBalance) {
            revert HarvestHandler__BalanceMismatch(s_usdc.balanceOf(address(s_fund)), expectedBalance);
        }
        if (s_token.balanceOf(address(s_fund)) != s_ghostDonatedDvr) {
            revert HarvestHandler__DvrBalanceMismatch(s_token.balanceOf(address(s_fund)), s_ghostDonatedDvr);
        }
        if (s_token.totalMinted() != s_ghostMinted) {
            revert HarvestHandler__MintMismatch(s_token.totalMinted(), s_ghostMinted);
        }
        if (s_pool.reserveDvr() != s_reserveDvr || s_pool.reserveUsdc() != s_reserveUsdc) {
            revert HarvestHandler__ReserveMismatch(s_pool.reserveDvr(), s_pool.reserveUsdc());
        }
        if (s_roundKnown) {
            (bool harvested, uint256 roundId) = s_fund.lastHarvestedRound();
            if (!harvested || roundId != s_lastRound) {
                revert HarvestHandler__RoundMismatch(roundId, s_lastRound);
            }
        }
        if (s_kAfter < s_kBefore) {
            revert HarvestHandler__KDecreased(s_kBefore, s_kAfter);
        }
    }

    modifier tracksMain() {
        uint256 beforeK = s_pool.reserveDvr() * s_pool.reserveUsdc();
        _;
        uint256 afterK = s_pool.reserveDvr() * s_pool.reserveUsdc();
        if (afterK < beforeK) {
            revert HarvestHandler__KDecreased(beforeK, afterK);
        }
        s_kBefore = beforeK;
        s_kAfter = afterK;
        _checkMain();
    }

    function _one(IMockFarm farm_) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm_;
    }
}
