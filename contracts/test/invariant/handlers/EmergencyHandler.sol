// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IMockFarm} from "../../../src/interfaces/IMockFarm.sol";
import {CruiseControl} from "../../../src/CruiseControl.sol";
import {DemoDriverClock} from "../../../src/DemoDriverClock.sol";
import {DegenDriver} from "../../../src/DegenDriver.sol";
import {DriverToken} from "../../../src/DriverToken.sol";
import {MockFarm} from "../../../src/MockFarm.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";
import {OfficialPool} from "../../../src/OfficialPool.sol";
import {RoundSchedule} from "../../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../../src/TreasuryFund.sol";
import {HaltingDriverClock} from "../../mocks/HaltingDriverClock.sol";
import {MappedBallot} from "../../mocks/HarvestMocks.sol";

contract EmergencyHandler is Test {
    uint256 internal constant S1 = 3;
    uint256 internal constant S2 = 1;
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant EPOCH = 30 days;
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;
    uint256 internal constant MAIN_APR = 16_000;
    uint256 internal constant RESERVE = 1_000_000_000_000 * 10 ** 6;
    uint256 internal constant HALT_RESERVE = 1_000 * 10 ** 6;
    uint256 internal constant CRUISE_PRINCIPAL = 15_000 * 10 ** 6;
    uint256 internal constant CRUISE_PLUS = 15_000_000_001;
    uint256 internal constant CRUISE_30_DAYS = 61_643_835;
    uint256 internal constant TOP_UP = 3_750_000_000;
    uint256 internal constant FUND_2_BPS = 4_000;

    MockUSDC public s_usdc;
    DriverToken public s_token;
    DemoDriverClock public s_clock;
    OfficialPool public s_pool;
    MockFarm public s_cruiseFarm;
    MockFarm public s_degenFarm;
    RoundSchedule public s_schedule;
    MappedBallot public s_ballot;
    CruiseControl public s_cruise;
    DegenDriver public s_degen;

    uint256 public s_idle1;
    uint256 public s_principal1;
    uint256 public s_idle2;
    uint256 public s_principal2;
    uint256 public s_donated1;
    uint256 public s_donated2;
    uint256 public s_ghostSum;
    uint256 public s_pending2;
    uint256 public s_returned;
    uint256 public s_returnCredits;
    bool public s_farm1;
    bool public s_farm2;
    bool internal s_exited1;
    bool internal s_exited2;
    bool internal s_ranForced;
    uint256 internal s_tax2;
    uint256 internal s_checkpoint2;

    uint256 public s_withPrincipal;
    uint256 public s_emptyActive;
    uint256 public s_twice;
    uint256 public s_afterSwitch;
    uint256 public s_fund1Idle;
    uint256 public s_harvestAfter;
    uint256 public s_rebalanceAfter;
    uint256 public s_topUpAfter;
    uint256 public s_pausedRejected;
    uint256 public s_halted;
    uint256 public s_alreadyPaused;
    uint256 public s_emptyReason;
    uint256 public s_unauthorized;
    uint256 public s_direct;
    uint256 public s_both;

    address internal s_stranger = makeAddr("emergencyStranger");

    error EmergencyHandler__ValueMismatch(uint256 actual, uint256 ghost);
    error EmergencyHandler__BalanceMismatch(uint256 actual, uint256 ghost);
    error EmergencyHandler__SumChanged(uint256 beforeSum, uint256 afterSum);
    error EmergencyHandler__FormulaMismatch(uint256 actual, uint256 expected);
    error EmergencyHandler__UnexpectedSuccess();
    error EmergencyHandler__UnexpectedRevert(bytes reason);
    error EmergencyHandler__ForcedMissed();
    error EmergencyHandler__RunningTotal(uint256 recorded, uint256 gained);

    struct Scene {
        DemoDriverClock clock;
        CruiseControl cruise;
        DegenDriver degen;
        MockFarm farm1;
        MockFarm farm2;
        MockFarm farm3;
        MappedBallot ballot;
    }

    constructor() {
        s_usdc = new MockUSDC(address(this));
        s_token = new DriverToken(address(this));
        s_clock = new DemoDriverClock(address(this));
        TaxSplitter splitter = new TaxSplitter(s_usdc, address(this));
        s_pool = new OfficialPool(s_token, s_usdc, splitter, address(this), 100);
        splitter.setPool(address(s_pool));
        s_token.mint(address(this), SEED_DVR);
        s_usdc.mint(address(this), type(uint128).max);
        s_token.approve(address(s_pool), SEED_DVR);
        s_usdc.approve(address(s_pool), SEED_USDC);
        s_pool.addLiquidity(SEED_DVR, SEED_USDC);

        s_cruiseFarm = new MockFarm(s_usdc, s_clock, 500, address(this));
        s_degenFarm = new MockFarm(s_usdc, s_clock, MAIN_APR, address(this));
        s_schedule = new RoundSchedule(s_clock, EPOCH);
        s_cruise =
            new CruiseControl(s_usdc, s_clock, s_schedule, splitter, s_pool, S1, S2, _one(s_cruiseFarm), address(this));
        s_degen = new DegenDriver(
            s_usdc, s_clock, s_schedule, splitter, s_pool, s_cruise, S1, S2, _one(s_degenFarm), address(this)
        );
        s_cruiseFarm.addDepositor(address(s_cruise));
        s_degenFarm.addDepositor(address(s_degen));
        s_usdc.approve(address(s_cruiseFarm), RESERVE);
        s_usdc.approve(address(s_degenFarm), RESERVE);
        s_cruiseFarm.fundRewards(RESERVE);
        s_degenFarm.fundRewards(RESERVE);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(s_cruise));
        splitter.setRecipient(TaxSplitter.FundId.Fund2, address(s_degen));
        s_ballot = new MappedBallot();
        s_degen.setBallot(s_ballot);
        s_cruise.setFund2(s_degen);
        s_usdc.approve(address(s_cruise), type(uint256).max);
        s_usdc.approve(address(s_degen), type(uint256).max);
        _check();
    }

    function supply1(uint256 amount) external {
        _campaign();
        _supply1(bound(amount, 1, 10_000));
    }

    function supply2(uint256 amount) external {
        _campaign();
        _supply2(bound(amount, 1, 10_000));
    }

    function deposit1(uint256 amount) external {
        _campaign();
        if (s_exited1) {
            return;
        }
        if (!s_farm1) {
            s_cruise.setStrategy(s_cruiseFarm);
            s_farm1 = true;
        }
        if (s_idle1 == 0) {
            return;
        }
        amount = bound(amount, 1, s_idle1);
        s_idle1 -= amount;
        s_principal1 += amount;
        s_cruise.deposit(amount);
        _check();
    }

    function harvest() external {
        _campaign();
        _harvest();
    }

    function topUp(uint256 amount) external {
        _campaign();
        uint256 cap = _move(S1, _value1(), S2, _value2());
        uint256 room = s_farm1 ? cap : (s_idle1 < cap ? s_idle1 : cap);
        amount = bound(amount, 0, room == cap ? cap + 1 : room);
        if (amount == 0 || amount > cap) {
            try s_cruise.topUpFund2(amount, "go") {
                revert EmergencyHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                _requireTopUpRevert(amount, cap, reason);
            }
            _check();
            return;
        }

        uint256 before = s_cruise.value() + s_degen.value();
        s_cruise.topUpFund2(amount, "go");
        _take(amount);
        if (s_farm2) {
            s_principal2 += amount;
        } else {
            s_idle2 += amount;
        }
        if (s_cruise.value() + s_degen.value() != before) {
            revert EmergencyHandler__SumChanged(before, s_cruise.value() + s_degen.value());
        }
        _check();
    }

    function donate(uint256 amount) external {
        _campaign();
        amount = bound(amount, 1, 1_000);
        s_donated2 += amount;
        s_usdc.mint(address(s_degen), amount);
        _check();
    }

    function exit1() external {
        _campaign();
        _exit(s_cruise, true);
    }

    function exit2() external {
        _campaign();
        _exit(s_degen, false);
    }

    function runForcedCases() external {
        _campaign();
    }

    function _campaign() private {
        if (s_ranForced) {
            return;
        }
        s_ranForced = true;
        _forceWithPrincipal();
        _forceEmptyActive();
        _forceTwice();
        _forceAfterSwitch();
        _forceFund1Idle();
        _forceHarvestAfter();
        _forceRebalanceAfter();
        _forceTopUpAfter();
        _forcePausedRejected();
        _forceHalted();
        _forceAlreadyPaused();
        _forceEmptyReason();
        _forceUnauthorized();
        _forceDirect();
        _forceBoth();
        _check();
    }

    function _supply1(uint256 amount) private {
        s_idle1 += amount;
        s_ghostSum += amount;
        s_cruise.supply(amount);
        _check();
    }

    function _supply2(uint256 amount) private {
        s_idle2 += amount;
        s_ghostSum += amount;
        s_degen.supply(amount);
        _check();
    }

    function _harvest() private {
        uint256 roundId = s_schedule.currentRound();
        s_ballot.setWinner(roundId, s_degenFarm);
        s_clock.advanceTime(EPOCH);
        bool switching = !s_farm2 && !s_exited2;
        uint256 rewards = 0;
        uint256 compound = 0;
        uint256 buyback = 0;
        if (s_farm2) {
            rewards = _earned(s_principal2, MAIN_APR, s_clock.currentTime() - s_checkpoint2);
            buyback = rewards / 2;
            compound = rewards - buyback;
        }
        uint256 taxIn = s_tax2;
        s_tax2 = 0;
        uint256 value2Before = s_principal2 + compound + s_idle2 + taxIn;
        uint256 value1Before = _value1();
        uint256 amount = _move(S2, value2Before, S1, value1Before);
        _bookBuyback(buyback);
        s_degen.harvest(0);
        s_ghostSum += compound + taxIn;
        if (s_farm2 || switching) {
            s_idle2 = 0;
            s_principal2 = value2Before - amount;
            s_farm2 = true;
            s_checkpoint2 = s_clock.currentTime();
        } else {
            s_idle2 = value2Before - amount;
            s_principal2 = 0;
        }
        if (s_farm1) {
            s_principal1 += amount;
        } else {
            s_idle1 += amount;
        }
        _check();
    }

    function _exit(TreasuryFund fund, bool fund1) private {
        bool active = fund1 ? s_farm1 : s_farm2;
        bool exited = fund1 ? s_exited1 : s_exited2;
        if (!active || exited) {
            return;
        }
        uint256 principal = fund1 ? s_principal1 : s_principal2;
        uint256 before = s_ghostSum;
        if (fund1) {
            s_idle1 += principal;
            s_principal1 = 0;
            s_farm1 = false;
            s_exited1 = true;
        } else {
            s_idle2 += principal;
            s_principal2 = 0;
            s_farm2 = false;
            s_exited2 = true;
        }
        fund.emergencyWithdraw("exit");
        uint256 afterSum = s_cruise.value() + s_degen.value();
        if (afterSum != before || s_ghostSum != before) {
            revert EmergencyHandler__SumChanged(before, afterSum);
        }
        _check();
    }

    function _forceWithPrincipal() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 80);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(80);
        uint256 before = scene.cruise.value() + scene.degen.value();
        scene.cruise.emergencyWithdraw("principal");
        _eq(scene.cruise.idle(), 80);
        _eq(scene.cruise.principal(), 0);
        _eq(scene.cruise.value(), 80);
        _eq(scene.cruise.value() + scene.degen.value(), before);
        if (address(scene.cruise.activeFarm()) != address(0) || !scene.farm1.paused()) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_withPrincipal += 1;
    }

    function _forceEmptyActive() private {
        Scene memory scene = _scene(1);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.emergencyWithdraw(" ");
        _eq(scene.cruise.idle(), 0);
        _eq(scene.cruise.principal(), 0);
        _eq(scene.cruise.strategyCount(), 0);
        if (scene.cruise.isStrategy(address(scene.farm1)) || !scene.farm1.paused()) {
            revert EmergencyHandler__ForcedMissed();
        }
        (address strategy, uint256 amount, string memory reason) = scene.cruise.lastEmergencyExit();
        if (strategy != address(scene.farm1) || amount != 0 || keccak256(bytes(reason)) != keccak256(bytes(" "))) {
            revert EmergencyHandler__FormulaMismatch(amount, 0);
        }
        s_emptyActive += 1;
    }

    function _forceTwice() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 25);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(25);
        scene.cruise.emergencyWithdraw("once");
        try scene.cruise.emergencyWithdraw("twice") {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _requireSelector(reason, TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        }
        _eq(scene.cruise.idle(), 25);
        s_twice += 1;
    }

    function _forceAfterSwitch() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 300);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(300);
        _pay(scene.degen, 100);
        scene.cruise.setFund2(scene.degen);
        scene.ballot.setWinner(0, scene.farm2);
        scene.ballot.setWinner(1, scene.farm3);
        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        uint256 ghost = 100;
        uint256 before = scene.cruise.value() + scene.degen.value();
        scene.degen.emergencyWithdraw("switch");
        _eq(scene.degen.idle(), ghost);
        _eq(scene.degen.principal(), 0);
        _eq(scene.cruise.value() + scene.degen.value(), before);
        _eq(address(scene.degen.strategyAt(0)) == address(scene.farm2) ? 1 : 0, 1);
        if (
            !scene.degen.isStrategy(address(scene.farm2)) || scene.degen.isStrategy(address(scene.farm3))
                || scene.farm2.paused() || !scene.farm3.paused()
        ) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_afterSwitch += 1;
    }

    function _forceFund1Idle() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 40);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(40);
        scene.cruise.emergencyWithdraw("delist");
        try scene.cruise.deposit(1) {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _requireSelector(reason, TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        }
        try scene.cruise.setStrategy(scene.farm1) {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _require(
                reason,
                keccak256(
                    abi.encodeWithSelector(TreasuryFund.TreasuryFund__StrategyNotAllowed.selector, address(scene.farm1))
                )
            );
        }
        _eq(scene.cruise.strategyCount(), 0);
        scene.clock.advanceTime(EPOCH);
        scene.cruise.harvest(0);
        _eq(scene.cruise.idle(), 40);
        _eq(scene.cruise.principal(), 0);
        s_fund1Idle += 1;
    }

    function _forceHarvestAfter() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 300);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(300);
        _pay(scene.degen, 100);
        scene.cruise.setFund2(scene.degen);
        scene.ballot.setWinner(0, scene.farm2);
        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        scene.degen.emergencyWithdraw("drift");
        uint256 idleBefore = scene.degen.idle();
        scene.ballot.setWinner(1, scene.farm2);
        scene.clock.advanceTime(EPOCH);
        vm.recordLogs();
        scene.degen.harvest(0);
        _sawIgnored(scene.degen, scene.farm2, 1);
        _eq(scene.degen.idle(), idleBefore);
        _eq(scene.degen.idle(), 100);
        if (address(scene.degen.activeFarm()) != address(0)) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_harvestAfter += 1;
    }

    function _forceRebalanceAfter() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 300);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(300);
        _pay(scene.degen, 100);
        scene.cruise.setFund2(scene.degen);
        scene.ballot.setWinner(0, scene.farm2);
        scene.ballot.setWinner(1, scene.farm2);
        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        scene.cruise.emergencyWithdraw("ratio");
        _pay(scene.degen, 100);
        uint256 fund1Before = scene.cruise.value();
        uint256 fund2Before = scene.degen.value();
        uint256 expected = _move(S2, fund2Before, S1, fund1Before);
        if (expected == 0) {
            revert EmergencyHandler__ForcedMissed();
        }
        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        _eq(scene.cruise.principal(), 0);
        _eq(scene.cruise.idle(), fund1Before + expected);
        _eq(scene.degen.value(), fund2Before - expected);
        if (scene.farm2.paused()) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_rebalanceAfter += 1;
    }

    function _forceTopUpAfter() private {
        Scene memory scene = _sceneShares(SHARE_1, SHARE_2, 500);
        _pay(scene.cruise, SHARE_1);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(SHARE_1);
        scene.cruise.setFund2(scene.degen);
        scene.cruise.emergencyWithdraw("revive");
        uint256 cap = _move(SHARE_1, scene.cruise.value(), SHARE_2, scene.degen.value());
        _eq(cap, TOP_UP);
        scene.cruise.topUpFund2(cap, "revive");
        _eq(scene.cruise.idle(), SHARE_1 - cap);
        _eq(scene.degen.idle(), cap);
        _eq(scene.degen.principal(), 0);
        if (address(scene.degen.activeFarm()) != address(0)) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_topUpAfter += 1;
    }

    function _forcePausedRejected() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 10);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(10);
        scene.cruise.emergencyWithdraw("pause");
        _rejectPaused(scene.cruise, scene.farm1);
        s_pausedRejected += 1;
    }

    function _forceHalted() private {
        HaltingDriverClock clock = new HaltingDriverClock();
        MockFarm farm = new MockFarm(s_usdc, clock, 500, address(this));
        RoundSchedule schedule = new RoundSchedule(clock, EPOCH);
        TaxSplitter splitter = s_pool.i_taxSplitter();
        CruiseControl cruise =
            new CruiseControl(s_usdc, clock, schedule, splitter, s_pool, SHARE_1, SHARE_2, _one(farm), address(this));
        farm.addDepositor(address(cruise));
        s_usdc.approve(address(farm), HALT_RESERVE);
        farm.fundRewards(HALT_RESERVE);
        s_usdc.approve(address(cruise), CRUISE_PRINCIPAL + 1);
        cruise.supply(CRUISE_PRINCIPAL + 1);
        cruise.setStrategy(farm);
        cruise.deposit(CRUISE_PRINCIPAL);
        clock.setTime(clock.currentTime() + EPOCH);
        cruise.deposit(1);
        _eq(farm.accrued(address(cruise)), CRUISE_30_DAYS);
        clock.halt();
        vm.recordLogs();
        cruise.emergencyWithdraw("halted");
        _sawForfeited(cruise, CRUISE_PLUS, CRUISE_30_DAYS);
        _eq(cruise.idle(), CRUISE_PLUS);
        _eq(cruise.value(), CRUISE_PLUS);
        _eq(farm.rewardReserve(), HALT_RESERVE);
        s_halted += 1;
    }

    function _forceAlreadyPaused() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 12);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(12);
        vm.prank(address(scene.cruise));
        scene.farm1.pause();
        uint256 before = scene.cruise.value() + scene.degen.value();
        scene.cruise.emergencyWithdraw("paused");
        _eq(scene.cruise.idle(), 12);
        _eq(scene.cruise.value() + scene.degen.value(), before);
        if (!scene.farm1.paused() || scene.cruise.isStrategy(address(scene.farm1))) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_alreadyPaused += 1;
    }

    function _forceEmptyReason() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 9);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(9);
        try scene.cruise.emergencyWithdraw("") {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _requireSelector(reason, TreasuryFund.TreasuryFund__EmptyReason.selector);
        }
        _eq(scene.cruise.principal(), 9);
        _eq(scene.cruise.idle(), 0);
        if (scene.farm1.paused()) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_emptyReason += 1;
    }

    function _forceUnauthorized() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 9);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(9);
        vm.prank(s_stranger);
        try scene.cruise.emergencyWithdraw("leak") {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _require(reason, keccak256(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_stranger)));
        }
        _eq(scene.cruise.principal(), 9);
        if (scene.farm1.paused()) {
            revert EmergencyHandler__ForcedMissed();
        }
        s_unauthorized += 1;
    }

    function _forceDirect() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 50);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(50);
        s_usdc.mint(address(scene.cruise), 123);
        s_usdc.mint(address(scene.farm1), 456);
        uint256 before = scene.cruise.value() + scene.degen.value();
        scene.cruise.emergencyWithdraw("direct");
        _eq(scene.cruise.idle(), 50);
        _eq(scene.cruise.value(), 50);
        _eq(scene.cruise.value() + scene.degen.value(), before);
        _eq(s_usdc.balanceOf(address(scene.cruise)), 173);
        _eq(s_usdc.balanceOf(address(scene.farm1)), 456);
        s_direct += 1;
    }

    function _forceBoth() private {
        Scene memory scene = _scene(1);
        _pay(scene.cruise, 300);
        scene.cruise.setStrategy(scene.farm1);
        scene.cruise.deposit(300);
        _pay(scene.degen, 100);
        scene.cruise.setFund2(scene.degen);
        scene.ballot.setWinner(0, scene.farm2);
        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        uint256 p1 = 300;
        uint256 p2 = 100;
        uint256 before = s_returned;
        uint256 sumBefore = scene.cruise.value() + scene.degen.value();
        scene.cruise.emergencyWithdraw("both");
        s_returned += p1;
        s_returnCredits += 1;
        if (s_returned != before + p1) {
            revert EmergencyHandler__RunningTotal(s_returned, p1);
        }
        _eq(scene.cruise.idle(), p1);
        _eq(scene.cruise.value() + scene.degen.value(), sumBefore);
        uint256 mid = s_returned;
        scene.degen.emergencyWithdraw("both");
        s_returned += p2;
        s_returnCredits += 1;
        if (s_returned != mid + p2) {
            revert EmergencyHandler__RunningTotal(s_returned, p2);
        }
        _eq(scene.degen.idle(), p2);
        _eq(scene.cruise.value() + scene.degen.value(), sumBefore);
        if (s_returnCredits != 2) {
            revert EmergencyHandler__RunningTotal(s_returnCredits, 2);
        }
        s_both += 1;
    }

    function _rejectPaused(CruiseControl cruise, MockFarm farm) private {
        vm.prank(address(cruise));
        try farm.deposit(1) {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _requireSelector(reason, Pausable.EnforcedPause.selector);
        }
        vm.prank(address(cruise));
        try farm.claim() {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _requireSelector(reason, Pausable.EnforcedPause.selector);
        }
        try farm.fundRewards(1) {
            revert EmergencyHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _requireSelector(reason, Pausable.EnforcedPause.selector);
        }
    }

    function _sawIgnored(DegenDriver degen, MockFarm farm, uint256 roundId) private view {
        bytes32 signature = keccak256("WinnerIgnored(uint256,address)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found = 0;
        uint256 count = logs.length;
        for (uint256 i = 0; i < count; i++) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != signature) {
                continue;
            }
            found += 1;
            if (logs[i].emitter != address(degen) || logs[i].topics[1] != bytes32(roundId)) {
                revert EmergencyHandler__FormulaMismatch(uint256(logs[i].topics[1]), roundId);
            }
            if (logs[i].topics[2] != bytes32(uint256(uint160(address(farm))))) {
                revert EmergencyHandler__FormulaMismatch(uint256(logs[i].topics[2]), uint256(uint160(address(farm))));
            }
        }
        if (found != 1) {
            revert EmergencyHandler__ForcedMissed();
        }
    }

    function _sawForfeited(CruiseControl cruise, uint256 principal, uint256 forfeited) private view {
        bytes32 signature = keccak256("EmergencyWithdrawn(address,uint256,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found = 0;
        uint256 count = logs.length;
        for (uint256 i = 0; i < count; i++) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != signature) {
                continue;
            }
            found += 1;
            if (logs[i].topics[1] != bytes32(uint256(uint160(address(cruise))))) {
                revert EmergencyHandler__FormulaMismatch(uint256(logs[i].topics[1]), uint256(uint160(address(cruise))));
            }
            (uint256 paid, uint256 dropped) = abi.decode(logs[i].data, (uint256, uint256));
            _eq(paid, principal);
            _eq(dropped, forfeited);
        }
        if (found != 1) {
            revert EmergencyHandler__ForcedMissed();
        }
    }

    function _scene(uint256 apr) private returns (Scene memory scene) {
        scene = _sceneShares(S1, S2, apr);
    }

    function _sceneShares(uint256 share1, uint256 share2, uint256 apr) private returns (Scene memory scene) {
        scene.clock = new DemoDriverClock(address(this));
        scene.farm1 = new MockFarm(s_usdc, scene.clock, apr, address(this));
        scene.farm2 = new MockFarm(s_usdc, scene.clock, apr, address(this));
        scene.farm3 = new MockFarm(s_usdc, scene.clock, apr, address(this));
        IMockFarm[] memory first = _one(scene.farm1);
        IMockFarm[] memory rest = new IMockFarm[](2);
        rest[0] = scene.farm2;
        rest[1] = scene.farm3;
        RoundSchedule schedule = new RoundSchedule(scene.clock, EPOCH);
        TaxSplitter splitter = s_pool.i_taxSplitter();
        scene.cruise =
            new CruiseControl(s_usdc, scene.clock, schedule, splitter, s_pool, share1, share2, first, address(this));
        scene.degen = new DegenDriver(
            s_usdc, scene.clock, schedule, splitter, s_pool, scene.cruise, share1, share2, rest, address(this)
        );
        scene.farm1.addDepositor(address(scene.cruise));
        scene.farm2.addDepositor(address(scene.degen));
        scene.farm3.addDepositor(address(scene.degen));
        scene.ballot = new MappedBallot();
        scene.degen.setBallot(scene.ballot);
    }

    function _pay(CruiseControl fund, uint256 amount) private {
        s_usdc.approve(address(fund), amount);
        fund.supply(amount);
    }

    function _pay(DegenDriver fund, uint256 amount) private {
        s_usdc.approve(address(fund), amount);
        fund.supply(amount);
    }

    function _one(IMockFarm farm) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm;
    }

    function _take(uint256 amount) private {
        uint256 fromIdle = s_idle1 < amount ? s_idle1 : amount;
        s_idle1 -= fromIdle;
        s_principal1 -= amount - fromIdle;
    }

    function _value1() private view returns (uint256 value_) {
        value_ = s_idle1 + s_principal1;
    }

    function _value2() private view returns (uint256 value_) {
        value_ = s_idle2 + s_principal2;
    }

    function _move(uint256 payerShare, uint256 payerValue, uint256 receiverShare, uint256 receiverValue)
        private
        pure
        returns (uint256 amount)
    {
        uint256 owed = receiverShare * payerValue;
        uint256 held = payerShare * receiverValue;
        if (owed <= held) {
            return 0;
        }
        amount = (owed - held) / (payerShare + receiverShare);
    }

    function _eq(uint256 actual, uint256 expected) private pure {
        if (actual != expected) {
            revert EmergencyHandler__FormulaMismatch(actual, expected);
        }
    }

    function _require(bytes memory reason, bytes32 expected) private pure {
        if (keccak256(reason) != expected) {
            revert EmergencyHandler__UnexpectedRevert(reason);
        }
    }

    function _requireSelector(bytes memory reason, bytes4 expected) private pure {
        if (keccak256(reason) != keccak256(abi.encodeWithSelector(expected))) {
            revert EmergencyHandler__UnexpectedRevert(reason);
        }
    }

    function _requireTopUpRevert(uint256 amount, uint256 cap, bytes memory reason) private pure {
        if (amount == 0) {
            _requireSelector(reason, TreasuryFund.TreasuryFund__ZeroAmount.selector);
            return;
        }
        _require(
            reason, keccak256(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, cap, amount))
        );
    }

    function _check() private view {
        uint256 value1 = _value1();
        uint256 value2 = _value2();
        if (s_cruise.value() != value1) {
            revert EmergencyHandler__ValueMismatch(s_cruise.value(), value1);
        }
        if (s_degen.value() != value2) {
            revert EmergencyHandler__ValueMismatch(s_degen.value(), value2);
        }
        if (value1 + value2 != s_ghostSum) {
            revert EmergencyHandler__SumChanged(value1 + value2, s_ghostSum);
        }
        if (s_usdc.balanceOf(address(s_cruise)) != s_idle1 + s_donated1) {
            revert EmergencyHandler__BalanceMismatch(s_usdc.balanceOf(address(s_cruise)), s_idle1 + s_donated1);
        }
        if (s_usdc.balanceOf(address(s_degen)) != s_idle2 + s_donated2 + s_pending2) {
            revert EmergencyHandler__BalanceMismatch(
                s_usdc.balanceOf(address(s_degen)), s_idle2 + s_donated2 + s_pending2
            );
        }
    }

    function _bookBuyback(uint256 buyback) private {
        if (buyback == 0) {
            return;
        }
        uint256 spend = buyback + s_pending2;
        (, bool deferred) = _quote(s_pool.reserveDvr(), s_pool.reserveUsdc(), spend);
        if (deferred) {
            s_pending2 = spend;
            return;
        }
        s_pending2 = 0;
        uint256 usdcTax = Math.mulDiv(spend, 100, BPS, Math.Rounding.Ceil);
        s_tax2 = Math.mulDiv(usdcTax, FUND_2_BPS, BPS);
    }

    function _earned(uint256 principal, uint256 apr, uint256 elapsed) private pure returns (uint256 rewards) {
        if (principal == 0 || elapsed == 0) {
            return 0;
        }
        rewards = Math.mulDiv(principal, apr * elapsed, BPS * YEAR);
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
}
