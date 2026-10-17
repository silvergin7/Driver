// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
import {MappedBallot} from "../../mocks/HarvestMocks.sol";

contract RebalanceHandler is Test {
    uint256 internal constant S1 = 3;
    uint256 internal constant S2 = 1;
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant EPOCH = 30 days;
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;
    uint256 internal constant DRIFT_APR = 16_000;
    uint256 internal constant MAIN_APR = 16_000;
    uint256 internal constant RESERVE = 1_000_000_000_000 * 10 ** 6;
    uint256 internal constant FUND_2_BPS = 4_000;

    MockUSDC public s_usdc;
    DriverToken public s_token;
    DemoDriverClock public s_clock;
    OfficialPool public s_pool;
    MockFarm public s_farm;
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
    uint256 public s_moved;
    uint256 public s_pending2;
    uint256 public s_tax2;
    bool public s_farm1;
    bool public s_farm2;
    bool internal s_armed;
    uint256 internal s_switchRound;
    uint256 internal s_checkpoint2;

    uint256 public s_below;
    uint256 public s_at;
    uint256 public s_above;
    uint256 public s_rounding;
    uint256 public s_doubleMove;
    uint256 public s_doubleTop;
    uint256 public s_capRevert;
    uint256 public s_zeroAmount;
    uint256 public s_emptyReason;
    uint256 public s_unauthorized;
    uint256 public s_noFarm;
    uint256 public s_idleThenFarm;
    uint256 public s_fund1Holds;
    uint256 public s_donation;
    uint256 public s_rewarded;
    uint256 public s_fromFarm;
    uint256 public s_rewardedMove;
    uint256 public s_topUpOnFarm;

    address internal s_stranger = makeAddr("rebalanceStranger");

    error RebalanceHandler__ValueMismatch(uint256 actual, uint256 ghost);
    error RebalanceHandler__BalanceMismatch(uint256 actual, uint256 ghost);
    error RebalanceHandler__SumChanged(uint256 beforeSum, uint256 afterSum);
    error RebalanceHandler__FloorLeft(uint256 floorAmount);
    error RebalanceHandler__TopUpShare(uint256 fund1Value, uint256 fund2Value);
    error RebalanceHandler__RunningTotal(uint256 recorded, uint256 gained);
    error RebalanceHandler__UnexpectedSuccess();
    error RebalanceHandler__UnexpectedRevert(bytes reason);
    error RebalanceHandler__FormulaMismatch(uint256 actual, uint256 expected);
    error RebalanceHandler__ForcedMissed();

    struct Scene {
        DemoDriverClock clock;
        CruiseControl cruise;
        DegenDriver degen;
        MockFarm farm;
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

        s_farm = new MockFarm(s_usdc, s_clock, MAIN_APR, address(this));
        IMockFarm[] memory farms = new IMockFarm[](1);
        farms[0] = s_farm;
        s_schedule = new RoundSchedule(s_clock, EPOCH);
        s_cruise = new CruiseControl(s_usdc, s_clock, s_schedule, splitter, s_pool, S1, S2, farms, address(this));
        s_degen = new DegenDriver(s_usdc, s_clock, s_schedule, splitter, s_pool, s_cruise, S1, S2, farms, address(this));
        s_farm.addDepositor(address(s_cruise));
        s_farm.addDepositor(address(s_degen));
        s_usdc.approve(address(s_farm), RESERVE);
        s_farm.fundRewards(RESERVE);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(s_cruise));
        splitter.setRecipient(TaxSplitter.FundId.Fund2, address(s_degen));
        s_ballot = new MappedBallot();
        s_degen.setBallot(s_ballot);
        s_cruise.setFund2(s_degen);
        _runForcedCases();
        _harvestFromFarm(1);
        _topUpOnFarm(1);
    }

    function supply1(uint256 amount) external {
        _supply1(bound(amount, 1, 10_000));
    }

    function supply2(uint256 amount) external {
        _supply2(bound(amount, 1, 10_000));
    }

    function harvest() external {
        _harvest();
    }

    function _harvest() private {
        s_clock.advanceTime(EPOCH);
        uint256 roundId = s_schedule.latestClosedRound();
        bool switching = !s_farm2 && s_armed && roundId == s_switchRound;
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
        s_moved += amount;
        _requireSum(value1Before + value2Before, _value1() + _value2());
        _requireFloor(S1, S2, _value1(), _value2());
        if (s_farm2 && amount > 0) {
            s_fromFarm += 1;
        }
        if (rewards > 0 && amount > 0) {
            s_rewardedMove += 1;
        }
        _check();
    }

    function topUpOnFarm(uint256 amount) external {
        _topUpOnFarm(amount);
    }

    function harvestFromFarm(uint256 amount) external {
        _harvestFromFarm(amount);
    }

    function topUp(uint256 amount) external {
        uint256 cap = _move(S1, _value1(), S2, _value2());
        amount = bound(amount, 0, cap + 1);
        if (amount == 0 || amount > cap) {
            try s_cruise.topUpFund2(amount, "go") {
                revert RebalanceHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                _requireTopUpRevert(amount, cap, reason);
            }
            _check();
            return;
        }

        uint256 before = _value1() + _value2();
        s_cruise.topUpFund2(amount, "go");
        _take(amount);
        if (s_farm2) {
            s_principal2 += amount;
            s_topUpOnFarm += 1;
        } else {
            s_idle2 += amount;
        }
        _requireSum(before, _value1() + _value2());
        _requireTopShare(S1, S2, _value1(), _value2());
        _requireFloor(S1, S2, _value1(), _value2());
        _check();
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1, 1_000);
        s_donated2 += amount;
        s_usdc.mint(address(s_degen), amount);
        _check();
    }

    function setFarm2() external {
        _setFarm2();
    }

    function park(uint256 amount) external {
        if (!s_farm1) {
            s_cruise.setStrategy(s_farm);
            s_farm1 = true;
        }
        if (s_idle1 == 0) {
            _check();
            return;
        }
        amount = bound(amount, 1, s_idle1);
        s_idle1 -= amount;
        s_principal1 += amount;
        s_cruise.deposit(amount);
        _check();
    }

    function runForcedCases() external {
        _runForcedCases();
    }

    function _supply1(uint256 amount) private {
        s_idle1 += amount;
        s_ghostSum += amount;
        s_usdc.approve(address(s_cruise), amount);
        s_cruise.supply(amount);
        _check();
    }

    function _supply2(uint256 amount) private {
        s_idle2 += amount;
        s_ghostSum += amount;
        s_usdc.approve(address(s_degen), amount);
        s_degen.supply(amount);
        _check();
    }

    function _setFarm2() private {
        uint256 roundId = s_schedule.currentRound();
        s_ballot.setWinner(roundId, s_farm);
        s_switchRound = roundId;
        s_armed = true;
        _check();
    }

    function _topUpOnFarm(uint256 amount) private {
        if (!s_farm2) {
            _setFarm2();
            _harvest();
        }
        uint256 cap = _move(S1, _value1(), S2, _value2());
        if (cap == 0) {
            uint256 denominator = S1 + S2;
            uint256 value1 = _value1();
            uint256 value2 = _value2();
            uint256 need = S1 * value2 + denominator;
            uint256 add = need > S2 * value1 ? (need - S2 * value1 + S2 - 1) / S2 : 1;
            _supply1(add);
            cap = _move(S1, _value1(), S2, _value2());
        }
        if (cap == 0) {
            revert RebalanceHandler__ForcedMissed();
        }
        amount = bound(amount, 1, cap);
        uint256 before = _value1() + _value2();
        s_cruise.topUpFund2(amount, "go");
        _take(amount);
        s_principal2 += amount;
        s_topUpOnFarm += 1;
        _requireSum(before, _value1() + _value2());
        _requireTopShare(S1, S2, _value1(), _value2());
        _requireFloor(S1, S2, _value1(), _value2());
        _check();
    }

    function _harvestFromFarm(uint256 amount) private {
        amount = bound(amount, 1, 10_000);
        if (!s_farm2) {
            _setFarm2();
            _harvest();
        }
        if (s_principal2 < 24) {
            uint256 projected = _value2OnNextHarvest(0);
            uint256 target = _targetValue2(_value1());
            if (projected < target) {
                _supply2(target - projected);
            }
            _harvest();
            if (s_principal2 < 24) {
                revert RebalanceHandler__ForcedMissed();
            }
        }
        _supply2(_idleForMove() + amount);
        uint256 fromBefore = s_fromFarm;
        uint256 rewardedBefore = s_rewardedMove;
        _harvest();
        if (s_fromFarm == fromBefore || s_rewardedMove == rewardedBefore) {
            revert RebalanceHandler__ForcedMissed();
        }
    }

    function _value2OnNextHarvest(uint256 add) private view returns (uint256 value2) {
        uint256 elapsed = s_clock.currentTime() + EPOCH - s_checkpoint2;
        uint256 rewards = _earned(s_principal2, MAIN_APR, elapsed);
        uint256 compound = rewards - rewards / 2;
        value2 = s_principal2 + compound + s_idle2 + s_tax2 + add;
    }

    function _targetValue2(uint256 value1) private pure returns (uint256 target) {
        uint256 denominator = S1 + S2;
        uint256 principalFloor = 24 * denominator / S2;
        uint256 forPrincipal = value1 >= principalFloor ? 0 : principalFloor - value1;
        uint256 forMove = (S2 * value1 + denominator + S1 - 1) / S1;
        target = forPrincipal > forMove ? forPrincipal : forMove;
    }

    function _idleForMove() private view returns (uint256 add) {
        uint256 denominator = S1 + S2;
        uint256 base = _value2OnNextHarvest(0);
        uint256 held = S2 * _value1();
        uint256 owed = S1 * base;
        if (owed > held && (owed - held) / denominator != 0) {
            return 0;
        }
        uint256 need = denominator + held;
        if (owed >= need) {
            return 1;
        }
        add = (need - owed + S1 - 1) / S1;
    }

    function _runForcedCases() private {
        if (s_rewarded != 0) {
            return;
        }
        _forceBelow();
        _forceAt();
        _forceAbove();
        _forceRounding();
        _forceDoubleMove();
        _forceDoubleTop();
        _forceCapRevert();
        _forceZeroAmount();
        _forceEmptyReason();
        _forceUnauthorized();
        _forceIdleThenFarm();
        _forceDonation();
        _forceRewarded();
        _check();
    }

    function _forceBelow() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 100, 100);
        scene.clock.advanceTime(EPOCH);
        try scene.degen.harvest(0) {
            revert RebalanceHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            bytes32 expected =
                keccak256(abi.encodeWithSelector(CruiseControl.CruiseControl__NotFund2.selector, address(scene.degen)));
            if (keccak256(reason) != expected) {
                revert RebalanceHandler__UnexpectedRevert(reason);
            }
        }
        scene.cruise.setFund2(scene.degen);
        _harvestMove(scene, S1, S2, 50);
        if (scene.cruise.idle() != 150 || scene.cruise.principal() != 0 || scene.degen.idle() != 50) {
            revert RebalanceHandler__FormulaMismatch(scene.cruise.value(), 150);
        }
        if (address(scene.cruise.activeFarm()) != address(0) || address(scene.degen.activeFarm()) != address(0)) {
            revert RebalanceHandler__FormulaMismatch(1, 0);
        }
        s_below += 1;
        s_noFarm += 1;
        s_fund1Holds += 1;
    }

    function _forceAt() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 150, 50);
        scene.cruise.setFund2(scene.degen);
        _harvestMove(scene, S1, S2, 0);
        s_at += 1;
    }

    function _forceAbove() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 180, 20);
        scene.cruise.setFund2(scene.degen);
        _harvestMove(scene, S1, S2, 0);
        if (scene.cruise.value() != 180 || scene.degen.value() != 20) {
            revert RebalanceHandler__FormulaMismatch(scene.cruise.value(), 180);
        }
        s_above += 1;
    }

    function _forceRounding() private {
        Scene memory scene = _scene(SHARE_1, SHARE_2, 1);
        _fill(scene, SHARE_1, SHARE_2 + 2);
        scene.cruise.setFund2(scene.degen);
        _harvestMove(scene, SHARE_1, SHARE_2, 1);
        _harvestMove(scene, SHARE_1, SHARE_2, 0);
        if (scene.cruise.value() != SHARE_1 + 1 || scene.degen.value() != SHARE_2 + 1) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.value(), SHARE_2 + 1);
        }
        s_rounding += 1;
    }

    function _forceDoubleMove() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 100, 100);
        scene.cruise.setFund2(scene.degen);
        uint256 start = scene.cruise.value();
        uint256 running = _harvestMove(scene, S1, S2, 50);
        _pay(scene.degen, 100);
        running += _harvestMove(scene, S1, S2, 75);
        if (scene.cruise.value() - start != running) {
            revert RebalanceHandler__RunningTotal(running, scene.cruise.value() - start);
        }
        s_doubleMove += 1;
    }

    function _forceDoubleTop() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 180, 20);
        scene.cruise.setFund2(scene.degen);
        uint256 start = scene.degen.value();
        uint256 running = _top(scene, S1, S2, 10);
        running += _top(scene, S1, S2, 20);
        if (scene.degen.value() - start != running) {
            revert RebalanceHandler__RunningTotal(running, scene.degen.value() - start);
        }
        s_doubleTop += 1;
    }

    function _forceCapRevert() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 180, 20);
        scene.cruise.setFund2(scene.degen);
        try scene.cruise.topUpFund2(31, "over") {
            revert RebalanceHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            _requireTopUpRevert(31, 30, reason);
        }
        s_capRevert += 1;
    }

    function _forceZeroAmount() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 180, 20);
        scene.cruise.setFund2(scene.degen);
        try scene.cruise.topUpFund2(0, "zero") {
            revert RebalanceHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            if (keccak256(reason) != keccak256(abi.encodeWithSelector(TreasuryFund.TreasuryFund__ZeroAmount.selector)))
            {
                revert RebalanceHandler__UnexpectedRevert(reason);
            }
        }
        s_zeroAmount += 1;
    }

    function _forceEmptyReason() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 180, 20);
        scene.cruise.setFund2(scene.degen);
        try scene.cruise.topUpFund2(30, "") {
            revert RebalanceHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(CruiseControl.CruiseControl__EmptyReason.selector))
            ) {
                revert RebalanceHandler__UnexpectedRevert(reason);
            }
        }
        s_emptyReason += 1;
    }

    function _forceUnauthorized() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 180, 20);
        scene.cruise.setFund2(scene.degen);
        vm.prank(s_stranger);
        try scene.cruise.topUpFund2(30, "no") {
            revert RebalanceHandler__UnexpectedSuccess();
        } catch (bytes memory reason) {
            bytes32 expected =
                keccak256(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_stranger));
            if (keccak256(reason) != expected) {
                revert RebalanceHandler__UnexpectedRevert(reason);
            }
        }
        s_unauthorized += 1;
    }

    function _forceIdleThenFarm() private {
        Scene memory scene = _scene(S1, S2, 1);
        scene.cruise.setStrategy(scene.farm);
        _pay(scene.cruise, 180);
        scene.cruise.deposit(170);
        _pay(scene.degen, 20);
        scene.cruise.setFund2(scene.degen);
        uint256 before = scene.cruise.value() + scene.degen.value();
        _top(scene, S1, S2, 30);
        if (scene.cruise.idle() != 0 || scene.cruise.principal() != 150 || scene.degen.idle() != 50) {
            revert RebalanceHandler__FormulaMismatch(scene.cruise.principal(), 150);
        }
        _requireSum(before, scene.cruise.value() + scene.degen.value());
        _requireTopShare(S1, S2, scene.cruise.value(), scene.degen.value());
        s_idleThenFarm += 1;
    }

    function _forceDonation() private {
        Scene memory scene = _scene(S1, S2, 1);
        _fill(scene, 150, 50);
        scene.cruise.setFund2(scene.degen);
        s_usdc.mint(address(scene.degen), 7);
        if (scene.degen.value() != 50 || s_usdc.balanceOf(address(scene.degen)) != 57) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.value(), 50);
        }
        _harvestMove(scene, S1, S2, 0);
        if (s_usdc.balanceOf(address(scene.degen)) != 57) {
            revert RebalanceHandler__BalanceMismatch(s_usdc.balanceOf(address(scene.degen)), 57);
        }
        s_donation += 1;
    }

    function _forceRewarded() private {
        TaxSplitter splitter = new TaxSplitter(s_usdc, address(this));
        OfficialPool pool = new OfficialPool(s_token, s_usdc, splitter, address(this), 100);
        splitter.setPool(address(pool));
        s_token.mint(address(this), SEED_DVR);
        s_token.approve(address(pool), SEED_DVR);
        s_usdc.approve(address(pool), SEED_USDC);
        pool.addLiquidity(SEED_DVR, SEED_USDC);
        Scene memory scene = _sceneOn(pool, splitter, SHARE_1, SHARE_2, DRIFT_APR);
        s_usdc.approve(address(scene.farm), 1_000_000 * 10 ** 6);
        scene.farm.fundRewards(1_000_000 * 10 ** 6);
        _fill(scene, SHARE_1, SHARE_2);
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, scene.farm);
        scene.degen.setBallot(ballot);
        scene.cruise.setFund2(scene.degen);

        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        _requireFloor(SHARE_1, SHARE_2, scene.cruise.value(), scene.degen.value());
        if (scene.degen.principal() != SHARE_2 || scene.degen.lastHarvest().rewards != 0) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.principal(), SHARE_2);
        }

        _harvestReward(scene, pool);
        s_rewarded += 1;
    }

    function _harvestReward(Scene memory scene, OfficialPool pool) private {
        scene.clock.advanceTime(EPOCH);
        uint256 rewards = _earned(SHARE_2, DRIFT_APR, EPOCH);
        uint256 buyback = rewards / 2;
        uint256 compound = rewards - buyback;
        _requireRewardNumbers(rewards, compound, buyback);
        uint256 valueBefore = SHARE_2 + compound;
        uint256 amount = _move(SHARE_2, valueBefore, SHARE_1, SHARE_1);
        (uint256 dvrOut, bool deferred) = _quote(pool.reserveDvr(), pool.reserveUsdc(), buyback);
        scene.degen.harvest(0);
        _requireRewardResult(scene, rewards, compound, buyback, valueBefore, amount, dvrOut, deferred);
    }

    function _requireRewardNumbers(uint256 rewards, uint256 compound, uint256 buyback) private pure {
        if (rewards != 657_534_246 || compound != 328_767_123 || buyback != 328_767_123) {
            revert RebalanceHandler__FormulaMismatch(rewards, 657_534_246);
        }
    }

    function _requireRewardResult(
        Scene memory scene,
        uint256 rewards,
        uint256 compound,
        uint256 buyback,
        uint256 valueBefore,
        uint256 amount,
        uint256 dvrOut,
        bool deferred
    ) private view {
        if (amount != 246_575_342) {
            revert RebalanceHandler__FormulaMismatch(amount, 246_575_342);
        }
        if (scene.degen.lastHarvest().rewards != rewards || scene.degen.lastHarvest().compounded != compound) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.lastHarvest().rewards, rewards);
        }
        if (deferred) {
            if (scene.degen.pendingBuyback() != buyback || scene.degen.dvrBoughtBack() != 0) {
                revert RebalanceHandler__FormulaMismatch(scene.degen.pendingBuyback(), buyback);
            }
        } else if (scene.degen.dvrBoughtBack() != dvrOut || scene.degen.lastHarvest().buybackSpent != buyback) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.dvrBoughtBack(), dvrOut);
        }
        (,, uint256 stored1, uint256 stored2, uint256 moved) = scene.degen.lastRebalance();
        if (stored1 != SHARE_1 || stored2 != valueBefore || moved != amount) {
            revert RebalanceHandler__FormulaMismatch(moved, amount);
        }
        uint256 afterSum = scene.cruise.value() + scene.degen.value();
        _requireSum(SHARE_1 + valueBefore, afterSum);
        _requireFloor(SHARE_1, SHARE_2, scene.cruise.value(), scene.degen.value());
        if (scene.cruise.value() != SHARE_1 + amount || scene.degen.value() != valueBefore - amount) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.value(), valueBefore - amount);
        }
    }

    function _harvestMove(Scene memory scene, uint256 share1, uint256 share2, uint256 expected)
        private
        returns (uint256 amount)
    {
        uint256 v1 = scene.cruise.value();
        uint256 v2 = scene.degen.value();
        amount = _move(share2, v2, share1, v1);
        if (amount != expected) {
            revert RebalanceHandler__FormulaMismatch(amount, expected);
        }
        uint256 before = v1 + v2;
        scene.clock.advanceTime(EPOCH);
        scene.degen.harvest(0);
        (,, uint256 stored1, uint256 stored2, uint256 moved) = scene.degen.lastRebalance();
        if (stored1 != v1 || stored2 != v2 || moved != amount) {
            revert RebalanceHandler__FormulaMismatch(moved, amount);
        }
        _requireSum(before, scene.cruise.value() + scene.degen.value());
        _requireFloor(share1, share2, scene.cruise.value(), scene.degen.value());
        if (scene.cruise.value() != v1 + amount || scene.degen.value() != v2 - amount) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.value(), v2 - amount);
        }
    }

    function _top(Scene memory scene, uint256 share1, uint256 share2, uint256 amount) private returns (uint256 paid) {
        uint256 v1 = scene.cruise.value();
        uint256 v2 = scene.degen.value();
        uint256 cap = _move(share1, v1, share2, v2);
        if (amount > cap) {
            revert RebalanceHandler__FormulaMismatch(amount, cap);
        }
        uint256 before = v1 + v2;
        scene.cruise.topUpFund2(amount, "forced");
        _requireSum(before, scene.cruise.value() + scene.degen.value());
        _requireTopShare(share1, share2, scene.cruise.value(), scene.degen.value());
        if (scene.cruise.value() != v1 - amount || scene.degen.value() != v2 + amount) {
            revert RebalanceHandler__FormulaMismatch(scene.degen.value(), v2 + amount);
        }
        paid = amount;
    }

    function _scene(uint256 share1, uint256 share2, uint256 apr) private returns (Scene memory scene) {
        scene = _sceneOn(s_pool, s_pool.i_taxSplitter(), share1, share2, apr);
    }

    function _sceneOn(OfficialPool pool, TaxSplitter splitter, uint256 share1, uint256 share2, uint256 apr)
        private
        returns (Scene memory scene)
    {
        scene.clock = new DemoDriverClock(address(this));
        scene.farm = new MockFarm(s_usdc, scene.clock, apr, address(this));
        IMockFarm[] memory farms = new IMockFarm[](1);
        farms[0] = scene.farm;
        RoundSchedule schedule = new RoundSchedule(scene.clock, EPOCH);
        scene.cruise =
            new CruiseControl(s_usdc, scene.clock, schedule, splitter, pool, share1, share2, farms, address(this));
        scene.degen = new DegenDriver(
            s_usdc, scene.clock, schedule, splitter, pool, scene.cruise, share1, share2, farms, address(this)
        );
        scene.farm.addDepositor(address(scene.cruise));
        scene.farm.addDepositor(address(scene.degen));
    }

    function _fill(Scene memory scene, uint256 fund1Amount, uint256 fund2Amount) private {
        _pay(scene.cruise, fund1Amount);
        _pay(scene.degen, fund2Amount);
    }

    function _pay(CruiseControl fund, uint256 amount) private {
        if (amount == 0) {
            return;
        }
        s_usdc.approve(address(fund), amount);
        fund.supply(amount);
    }

    function _pay(DegenDriver fund, uint256 amount) private {
        if (amount == 0) {
            return;
        }
        s_usdc.approve(address(fund), amount);
        fund.supply(amount);
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

    function _requireFloor(uint256 share1, uint256 share2, uint256 fund1Value, uint256 fund2Value) private pure {
        uint256 owed = share1 * fund2Value;
        uint256 held = share2 * fund1Value;
        if (owed <= held) {
            return;
        }
        uint256 floorAmount = (owed - held) / (share1 + share2);
        if (floorAmount != 0) {
            revert RebalanceHandler__FloorLeft(floorAmount);
        }
    }

    function _requireTopShare(uint256 share1, uint256 share2, uint256 fund1Value, uint256 fund2Value) private pure {
        if (share2 * fund1Value < share1 * fund2Value) {
            revert RebalanceHandler__TopUpShare(fund1Value, fund2Value);
        }
    }

    function _requireSum(uint256 beforeSum, uint256 afterSum) private pure {
        if (beforeSum != afterSum) {
            revert RebalanceHandler__SumChanged(beforeSum, afterSum);
        }
    }

    function _requireTopUpRevert(uint256 amount, uint256 cap, bytes memory reason) private pure {
        if (amount == 0) {
            if (keccak256(reason) != keccak256(abi.encodeWithSelector(TreasuryFund.TreasuryFund__ZeroAmount.selector)))
            {
                revert RebalanceHandler__UnexpectedRevert(reason);
            }
            return;
        }
        bytes32 expected =
            keccak256(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, cap, amount));
        if (keccak256(reason) != expected) {
            revert RebalanceHandler__UnexpectedRevert(reason);
        }
    }

    function _check() private view {
        uint256 value1 = _value1();
        uint256 value2 = _value2();
        if (s_cruise.value() != value1) {
            revert RebalanceHandler__ValueMismatch(s_cruise.value(), value1);
        }
        if (s_degen.value() != value2) {
            revert RebalanceHandler__ValueMismatch(s_degen.value(), value2);
        }
        if (value1 + value2 != s_ghostSum) {
            revert RebalanceHandler__SumChanged(value1 + value2, s_ghostSum);
        }
        if (s_usdc.balanceOf(address(s_cruise)) != s_idle1 + s_donated1) {
            revert RebalanceHandler__BalanceMismatch(s_usdc.balanceOf(address(s_cruise)), s_idle1 + s_donated1);
        }
        if (s_usdc.balanceOf(address(s_degen)) != s_idle2 + s_donated2 + s_pending2) {
            revert RebalanceHandler__BalanceMismatch(
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
