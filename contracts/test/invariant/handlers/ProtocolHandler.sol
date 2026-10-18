// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";
import {IMockFarm} from "../../../src/interfaces/IMockFarm.sol";
import {IOfficialPool} from "../../../src/interfaces/IOfficialPool.sol";
import {CruiseControl} from "../../../src/CruiseControl.sol";
import {DegenDriver} from "../../../src/DegenDriver.sol";
import {DemoDriverClock} from "../../../src/DemoDriverClock.sol";
import {DriverFaucet} from "../../../src/DriverFaucet.sol";
import {DriverToken} from "../../../src/DriverToken.sol";
import {DriverVote} from "../../../src/DriverVote.sol";
import {MockFarm} from "../../../src/MockFarm.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../../../src/MockUsdcFaucet.sol";
import {OfficialPool} from "../../../src/OfficialPool.sol";
import {RoundSchedule} from "../../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../../src/TreasuryFund.sol";
import {DeployDriverToken} from "../../../script/DeployDriverToken.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

contract ProtocolHandler is Test {
    uint256 internal constant ACTORS = 3;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant TAX = 100;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant EPOCH = 30 days;
    uint256 internal constant NONE = type(uint256).max;
    uint256 internal constant CRUISE = 0;
    uint256 internal constant HIGHWAY = 1;
    uint256 internal constant AUTOBAHN = 2;
    uint256 internal constant DRIFT = 3;
    uint256 internal constant ACTOR_DVR = 1_000 ether;
    uint256 internal constant CLAIM_DVR = 10 ether;
    uint256 internal constant CLAIM_USDC = 100 * 10 ** 6;
    uint256 internal constant MIN_BUY = 10_000;
    uint256 internal constant MIN_SELL = 10 ** 15;
    uint256 internal constant BUY_FORCED = 10 * 10 ** 6;
    uint256 internal constant SELL_FORCED = 10 ether;
    uint256 internal constant LOCK_FORCED = 100 ether;
    uint256 internal constant UNLOCK_FORCED = 40 ether;
    uint256 internal constant BURN_C = 1_518_101_641_108_824_149_660;
    uint256 internal constant MOVE_D = 238_990_821;
    uint256 internal constant CAP_E = 15_972_525;

    DeployDriverToken.Deployed private s_deployed;
    DemoDriverClock private s_clock;
    address private s_owner;
    address private s_script;

    address[3] public s_actor;
    uint256[3] public s_lock;
    uint256[4] public s_principal;
    uint256[4] public s_farmReserve;
    address[4] public s_farm;

    uint256 public s_idle1;
    uint256 public s_idle2;
    uint256 public s_held1;
    uint256 public s_held2;
    uint256 public s_pending1;
    uint256 public s_pending2;
    uint256 public s_value1;
    uint256 public s_value2;
    uint256 public s_tax1;
    uint256 public s_tax2;
    uint256 public s_tax3;
    uint256 public s_reserveDvr;
    uint256 public s_reserveUsdc;
    uint256 public s_ghostK;
    uint256 public s_ghostBurned;
    uint256 public s_ghostDvr;
    uint256 public s_ghostUsdc;
    uint256 public s_ghostOffset;
    uint256 public immutable i_fund1;
    uint256 public immutable i_fund2;
    uint256 public immutable i_faucetStart;
    uint256 public s_dvrPaid;

    uint256 public s_dvrClaims;
    uint256 public s_usdcClaims;
    uint256 public s_buys;
    uint256 public s_sells;
    uint256 public s_revoted;
    uint256 public s_buyback;
    uint256 public s_capped;
    uint256 public s_switched;
    uint256 public s_rebalance;
    uint256 public s_topUp;
    uint256 public s_tieKept;
    uint256 public s_unlockAfterVote;
    uint256 public s_exit1;
    uint256 public s_exit2;
    uint256 public s_ignored;
    uint256 public s_harvestAfterExit;
    bool public s_exits;
    address[4] public s_exited;
    uint256 public s_exitedCount;

    uint256[3] internal s_list;
    uint256 internal s_listCount;
    uint256 internal s_active1;
    uint256 internal s_active2;
    uint256[4] internal s_accrued;
    uint256[4] internal s_last;
    uint256[4] internal s_apr;
    uint256[3] internal s_walletDvr;
    uint256[3] internal s_walletUsdc;
    mapping(uint256 roundId => mapping(uint256 actor => address farm)) internal s_choice;
    mapping(uint256 roundId => mapping(address farm => uint256 weight)) internal s_tally;
    uint256 internal s_openedAt;
    bool internal s_did1;
    bool internal s_did2;
    uint256 internal s_round1;
    uint256 internal s_round2;
    bool internal s_ran;

    error ProtocolHandler__TransferFailed();
    error ProtocolHandler__StartMismatch(uint256 actual, uint256 expected);
    error ProtocolHandler__ClaimMissed();
    error ProtocolHandler__RevoteMissed();
    error ProtocolHandler__BurnMismatch(uint256 actual, uint256 expected);
    error ProtocolHandler__SwitchMissed();
    error ProtocolHandler__MoveMismatch(uint256 actual, uint256 expected);
    error ProtocolHandler__CapMismatch(uint256 actual, uint256 expected);
    error ProtocolHandler__UnlockMissed();
    error ProtocolHandler__TieMissed();
    error ProtocolHandler__ExitMissed();
    error ProtocolHandler__IgnoredMissed();
    error ProtocolHandler__UnexpectedSuccess();
    error ProtocolHandler__KDecreased(uint256 beforeProduct, uint256 afterProduct);

    struct Quote {
        uint256 amountIn;
        uint256 amountOut;
        uint256 usdcTax;
        uint256 newReserveDvr;
        uint256 newReserveUsdc;
        bool ok;
    }

    constructor(bool exits) {
        s_exits = exits;
        DeployDriverToken deployScript = new DeployDriverToken();
        s_script = address(deployScript);
        s_deployed = deployScript.run();
        s_clock = DemoDriverClock(address(s_deployed.clock));
        s_owner = s_deployed.token.owner();
        s_openedAt = block.timestamp;

        HelperConfig helper = new HelperConfig();
        uint256 fund1 = helper.FUND_1_USDC();
        uint256 fund2 = helper.FUND_2_USDC();
        uint256 poolDvr = helper.POOL_ALLOCATION();
        uint256 poolUsdc = helper.POOL_USDC();
        uint256 cruiseReserve = helper.CRUISE_RESERVE();
        uint256 highwayReserve = helper.HIGHWAY_RESERVE();
        uint256 autobahnReserve = helper.AUTOBAHN_RESERVE();
        uint256 driftReserve = helper.DRIFT_RESERVE();
        i_faucetStart = helper.FAUCET_ALLOCATION();
        i_fund1 = fund1;
        i_fund2 = fund2;
        if (s_deployed.schedule.i_start() != s_openedAt) {
            revert ProtocolHandler__StartMismatch(s_deployed.schedule.i_start(), s_openedAt);
        }
        s_farm[CRUISE] = address(s_deployed.cruise);
        s_farm[HIGHWAY] = address(s_deployed.highway);
        s_farm[AUTOBAHN] = address(s_deployed.autobahn);
        s_farm[DRIFT] = address(s_deployed.drift);
        s_apr[CRUISE] = helper.CRUISE_APR_BPS();
        s_apr[HIGHWAY] = helper.HIGHWAY_APR_BPS();
        s_apr[AUTOBAHN] = helper.AUTOBAHN_APR_BPS();
        s_apr[DRIFT] = helper.DRIFT_APR_BPS();
        s_farmReserve[CRUISE] = cruiseReserve;
        s_farmReserve[HIGHWAY] = highwayReserve;
        s_farmReserve[AUTOBAHN] = autobahnReserve;
        s_farmReserve[DRIFT] = driftReserve;
        s_principal[CRUISE] = fund1;
        s_last[CRUISE] = s_openedAt;
        s_active1 = CRUISE;
        s_active2 = NONE;
        s_list[0] = HIGHWAY;
        s_list[1] = AUTOBAHN;
        s_list[2] = DRIFT;
        s_listCount = 3;
        s_idle2 = fund2;
        s_value1 = fund1;
        s_value2 = fund2;
        s_reserveDvr = poolDvr;
        s_reserveUsdc = poolUsdc;
        s_ghostK = poolDvr * poolUsdc;
        s_ghostDvr = poolDvr + i_faucetStart;
        s_ghostUsdc = poolUsdc + fund1 + fund2 + cruiseReserve + highwayReserve + autobahnReserve + driftReserve;

        for (uint256 i = 0; i < ACTORS; i++) {
            s_actor[i] = makeAddr(string.concat("protocolActor", vm.toString(i)));
            s_walletDvr[i] = ACTOR_DVR;
            vm.prank(s_owner);
            if (!s_deployed.token.transfer(s_actor[i], ACTOR_DVR)) revert ProtocolHandler__TransferFailed();
            vm.startPrank(s_actor[i]);
            s_deployed.token.approve(address(s_deployed.pool), type(uint256).max);
            s_deployed.token.approve(address(s_deployed.vote), type(uint256).max);
            s_deployed.usdc.approve(address(s_deployed.pool), type(uint256).max);
            vm.stopPrank();
        }
    }

    function claimDvr(uint256 actorSeed) external {
        _enter();
        _claimDvr(bound(actorSeed, 0, ACTORS - 1));
    }

    function claimUsdc(uint256 actorSeed) external {
        _enter();
        _claimUsdc(bound(actorSeed, 0, ACTORS - 1));
    }

    function buy(uint256 actorSeed, uint256 amount) external {
        _enter();
        uint256 actor = bound(actorSeed, 0, ACTORS - 1);
        uint256 wallet = s_walletUsdc[actor];
        if (wallet < MIN_BUY) return;
        uint256 maxIn = s_reserveUsdc / 10;
        if (maxIn > wallet) maxIn = wallet;
        if (maxIn < MIN_BUY) return;
        _buy(actor, bound(amount, MIN_BUY, maxIn));
    }

    function sell(uint256 actorSeed, uint256 amount) external {
        _enter();
        uint256 actor = bound(actorSeed, 0, ACTORS - 1);
        uint256 wallet = s_walletDvr[actor];
        if (wallet < MIN_SELL) return;
        uint256 maxIn = s_reserveDvr / 10;
        if (maxIn > wallet) maxIn = wallet;
        if (maxIn < MIN_SELL) return;
        _sell(actor, bound(amount, MIN_SELL, maxIn));
    }

    function harvest1() external {
        _enter();
        _harvestExternal(true);
    }

    function harvest2() external {
        _enter();
        _harvestExternal(false);
    }

    function topUp(uint256 amount) external {
        _enter();
        _sync(true);
        _sync(false);
        uint256 cap = _move(i_fund1, s_value1, i_fund2, s_value2);
        if (cap == 0) return;
        _topUp(bound(amount, 1, cap));
    }

    function lock(uint256 actorSeed, uint256 amount) external {
        _enter();
        uint256 actor = bound(actorSeed, 0, ACTORS - 1);
        if (s_walletDvr[actor] == 0) return;
        _lock(actor, bound(amount, 1, s_walletDvr[actor]));
    }

    function vote(uint256 actorSeed, uint256 farmSeed) external {
        _enter();
        if (s_listCount == 0) return;
        uint256 actor = bound(actorSeed, 0, ACTORS - 1);
        if (s_lock[actor] == 0) {
            vm.prank(s_actor[actor]);
            try s_deployed.vote.vote(IMockFarm(s_farm[s_list[0]])) {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (_selector(reason) != DriverVote.DriverVote__NothingLocked.selector) _bubble(reason);
            }
            return;
        }
        _vote(actor, s_farm[s_list[bound(farmSeed, 0, s_listCount - 1)]]);
    }

    function unlock(uint256 actorSeed, uint256 amount) external {
        _enter();
        uint256 actor = bound(actorSeed, 0, ACTORS - 1);
        if (s_choice[_round()][actor] != address(0)) {
            vm.prank(s_actor[actor]);
            try s_deployed.vote.unlock(1) {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (_selector(reason) != DriverVote.DriverVote__Voted.selector) _bubble(reason);
            }
            return;
        }
        if (s_lock[actor] == 0) return;
        _unlock(actor, bound(amount, 1, s_lock[actor]));
    }

    function skipTime(uint256 secondsForward) external {
        _enter();
        _skip(bound(secondsForward, 1, EPOCH));
    }

    function warp(uint256 secondsForward) external {
        _enter();
        vm.warp(block.timestamp + bound(secondsForward, 1, 2 days));
    }

    function exit1() external {
        _enter();
        _exitExternal(true);
    }

    function exit2() external {
        _enter();
        _exitExternal(false);
    }

    function token() external view returns (DriverToken) {
        return s_deployed.token;
    }

    function dvrFaucet() external view returns (DriverFaucet) {
        return s_deployed.dvrFaucet;
    }

    function usdc() external view returns (MockUSDC) {
        return s_deployed.usdc;
    }

    function usdcFaucet() external view returns (MockUsdcFaucet) {
        return s_deployed.usdcFaucet;
    }

    function clock() external view returns (DemoDriverClock) {
        return s_clock;
    }

    function splitter() external view returns (TaxSplitter) {
        return s_deployed.splitter;
    }

    function pool() external view returns (OfficialPool) {
        return s_deployed.pool;
    }

    function cruise() external view returns (MockFarm) {
        return s_deployed.cruise;
    }

    function highway() external view returns (MockFarm) {
        return s_deployed.highway;
    }

    function autobahn() external view returns (MockFarm) {
        return s_deployed.autobahn;
    }

    function drift() external view returns (MockFarm) {
        return s_deployed.drift;
    }

    function cruiseControl() external view returns (CruiseControl) {
        return s_deployed.cruiseControl;
    }

    function degenDriver() external view returns (DegenDriver) {
        return s_deployed.degenDriver;
    }

    function driverVote() external view returns (DriverVote) {
        return s_deployed.vote;
    }

    function schedule() external view returns (RoundSchedule) {
        return s_deployed.schedule;
    }

    function script() external view returns (address) {
        return s_script;
    }

    function lockSum() external view returns (uint256 sum) {
        sum = s_lock[0] + s_lock[1] + s_lock[2];
    }

    function _enter() internal {
        s_ghostK = s_reserveDvr * s_reserveUsdc;
        _campaign();
    }

    function _campaign() internal {
        if (s_ran) return;
        s_ran = true;
        if (!_claimDvr(0)) revert ProtocolHandler__ClaimMissed();
        s_dvrClaims += 1;
        if (!_claimUsdc(0)) revert ProtocolHandler__ClaimMissed();
        s_usdcClaims += 1;
        _buy(0, BUY_FORCED);
        s_buys += 1;
        _sell(0, SELL_FORCED);
        s_sells += 1;
        _lock(0, LOCK_FORCED);
        _vote(0, s_farm[HIGHWAY]);
        if (!_vote(0, s_farm[DRIFT])) revert ProtocolHandler__RevoteMissed();
        s_revoted += 1;

        _expectNoClosed(true);
        _expectNoClosed(false);

        _skip(EPOCH);
        (uint256 burned,) = _harvestFund(true);
        if (burned != BURN_C) revert ProtocolHandler__BurnMismatch(burned, BURN_C);
        s_buyback += 1;
        if (_mintAgain()) s_capped += 1;
        _harvestFund(false);
        if (s_active2 != DRIFT || s_idle2 != 0 || s_principal[DRIFT] <= i_fund2) {
            revert ProtocolHandler__SwitchMissed();
        }
        if (address(s_deployed.degenDriver.activeFarm()) != s_farm[DRIFT]) revert ProtocolHandler__SwitchMissed();
        s_switched += 1;

        _skip(EPOCH);
        (, uint256 moved) = _harvestFund(false);
        if (moved != MOVE_D) revert ProtocolHandler__MoveMismatch(moved, MOVE_D);
        s_rebalance += 1;
        _harvestFund(true);

        _skip(EPOCH);
        _harvestFund(true);
        uint256 cap = _move(i_fund1, s_value1, i_fund2, s_value2);
        if (cap != CAP_E) revert ProtocolHandler__CapMismatch(cap, CAP_E);
        _topUp(cap);
        s_topUp += 1;

        _keepTie();
        if (s_exits) _exitCampaign();

        if (s_choice[_round()][0] != address(0) || s_lock[0] < UNLOCK_FORCED) revert ProtocolHandler__UnlockMissed();
        _unlock(0, UNLOCK_FORCED);
        s_unlockAfterVote += 1;
    }

    function _expectNoClosed(bool fund1) internal {
        vm.prank(s_owner);
        if (fund1) {
            try s_deployed.cruiseControl.harvest(0) {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (_selector(reason) != RoundSchedule.RoundSchedule__NoClosedRound.selector) _bubble(reason);
            }
        } else {
            try s_deployed.degenDriver.harvest(0) {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (_selector(reason) != RoundSchedule.RoundSchedule__NoClosedRound.selector) _bubble(reason);
            }
        }
    }

    function _mintAgain() internal returns (bool capped) {
        vm.prank(s_owner);
        try s_deployed.token.mint(s_owner, 1) {
            return false;
        } catch (bytes memory reason) {
            if (_selector(reason) != DriverToken.DriverToken__LifetimeMintCapExceeded.selector) _bubble(reason);
            return true;
        }
    }

    function _harvestExternal(bool fund1) internal {
        uint256 openRound = _round();
        if (openRound == 0) {
            _expectNoClosed(fund1);
            return;
        }
        uint256 closed = openRound - 1;
        bool done = fund1 ? s_did1 : s_did2;
        uint256 last = fund1 ? s_round1 : s_round2;
        if (done && closed <= last) {
            vm.prank(s_owner);
            if (fund1) {
                try s_deployed.cruiseControl.harvest(0) {
                    revert ProtocolHandler__UnexpectedSuccess();
                } catch (bytes memory reason) {
                    if (_selector(reason) != TreasuryFund.TreasuryFund__RoundAlreadyHarvested.selector) {
                        _bubble(reason);
                    }
                }
            } else {
                try s_deployed.degenDriver.harvest(0) {
                    revert ProtocolHandler__UnexpectedSuccess();
                } catch (bytes memory reason) {
                    if (_selector(reason) != TreasuryFund.TreasuryFund__RoundAlreadyHarvested.selector) {
                        _bubble(reason);
                    }
                }
            }
            return;
        }
        _harvestFund(fund1);
    }

    function _harvestFund(bool fund1) internal returns (uint256 burned, uint256 moved) {
        uint256 active = fund1 ? s_active1 : s_active2;
        uint256 taxReleased = fund1 ? s_tax1 : s_tax2;
        uint256 held = fund1 ? s_held1 : s_held2;
        if (fund1) {
            s_tax1 = 0;
            s_held1 = 0;
        } else {
            s_tax2 = 0;
            s_held2 = 0;
        }
        uint256 rewards = held;
        uint256 idle_ = (fund1 ? s_idle1 : s_idle2) + taxReleased;
        uint256 buybackHalf;
        if (active == NONE) {
            buybackHalf = rewards / 2;
            idle_ += rewards - buybackHalf;
        }
        uint256 endFarm = fund1 ? active : _chosen(_round() - 1, active);
        uint256 deployAmount;
        if (endFarm == NONE) {
            _setIdle(fund1, idle_);
        } else {
            _setIdle(fund1, 0);
            deployAmount = idle_;
        }
        if (active != NONE) {
            rewards += _claim(active);
            buybackHalf = rewards / 2;
            uint256 compounded = rewards - buybackHalf;
            if (compounded != 0) _deposit(active, compounded);
        }
        burned = _buyback(fund1, buybackHalf);
        if (endFarm != active) _switch(active, endFarm);
        if (deployAmount != 0) _deposit(fund1 ? s_active1 : s_active2, deployAmount);
        _sync(fund1);
        if (!fund1) moved = _rebalance();
        if (fund1) {
            s_did1 = true;
            s_round1 = _round() - 1;
            vm.prank(s_owner);
            s_deployed.cruiseControl.harvest(0);
        } else {
            s_did2 = true;
            s_round2 = _round() - 1;
            vm.prank(s_owner);
            s_deployed.degenDriver.harvest(0);
        }
    }

    function _rebalance() internal returns (uint256 amount) {
        _sync(true);
        _sync(false);
        amount = _move(i_fund2, s_value2, i_fund1, s_value1);
        if (amount == 0) return 0;
        uint256 fromIdle = s_idle2 < amount ? s_idle2 : amount;
        s_idle2 -= fromIdle;
        uint256 fromFarm = amount - fromIdle;
        if (fromFarm != 0) _withdraw(s_active2, fromFarm);
        if (s_active1 == NONE) s_idle1 += amount;
        else _deposit(s_active1, amount);
        _sync(true);
        _sync(false);
    }

    function _topUp(uint256 amount) internal {
        uint256 fromIdle = s_idle1 < amount ? s_idle1 : amount;
        s_idle1 -= fromIdle;
        uint256 fromFarm = amount - fromIdle;
        if (fromFarm != 0) _withdraw(s_active1, fromFarm);
        if (s_active2 == NONE) s_idle2 += amount;
        else _deposit(s_active2, amount);
        _sync(true);
        _sync(false);
        vm.prank(s_owner);
        s_deployed.cruiseControl.topUpFund2(amount, "topup");
    }

    function _switch(uint256 previous, uint256 nextFarm) internal {
        s_active2 = nextFarm;
        if (previous == NONE) return;
        uint256 principal = s_principal[previous];
        s_held2 += _claim(previous);
        if (principal != 0) {
            _withdraw(previous, principal);
            _deposit(nextFarm, principal);
        }
    }

    function _buyback(bool fund1, uint256 half) internal returns (uint256 burned) {
        if (half == 0) return 0;
        uint256 pending = fund1 ? s_pending1 : s_pending2;
        uint256 spend = half + pending;
        Quote memory quote = _quoteBuy(spend);
        if (!quote.ok) {
            if (fund1) s_pending1 = spend;
            else s_pending2 = spend;
            return 0;
        }
        if (fund1) s_pending1 = 0;
        else s_pending2 = 0;
        _applyReserves(quote);
        s_ghostBurned += quote.amountOut;
        s_ghostDvr -= quote.amountOut;
        burned = quote.amountOut;
    }

    function _buy(uint256 actor, uint256 amount) internal {
        Quote memory quote = _quoteBuy(amount);
        vm.prank(s_actor[actor]);
        if (!quote.ok) {
            try s_deployed.pool.swapExactInput(IOfficialPool.Direction.Buy, amount, 0, block.timestamp) returns (
                uint256
            ) {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (!_swapError(reason)) _bubble(reason);
            }
            return;
        }
        try s_deployed.pool.swapExactInput(IOfficialPool.Direction.Buy, amount, 0, block.timestamp) returns (uint256) {}
        catch (bytes memory reason) {
            _bubble(reason);
        }
        _applyReserves(quote);
        s_ghostUsdc += quote.amountIn;
        s_ghostDvr -= quote.amountOut;
        s_walletUsdc[actor] -= quote.amountIn;
        s_walletDvr[actor] += quote.amountOut;
    }

    function _sell(uint256 actor, uint256 amount) internal {
        Quote memory quote = _quoteSell(amount);
        vm.prank(s_actor[actor]);
        if (!quote.ok) {
            try s_deployed.pool.swapExactInput(IOfficialPool.Direction.Sell, amount, 0, block.timestamp) returns (
                uint256
            ) {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (!_swapError(reason)) _bubble(reason);
            }
            return;
        }
        try s_deployed.pool.swapExactInput(IOfficialPool.Direction.Sell, amount, 0, block.timestamp) returns (
            uint256
        ) {}
        catch (bytes memory reason) {
            _bubble(reason);
        }
        _applyReserves(quote);
        s_ghostUsdc -= quote.amountOut;
        s_ghostDvr += quote.amountIn;
        s_walletDvr[actor] -= quote.amountIn;
        s_walletUsdc[actor] += quote.amountOut;
    }

    function _claimDvr(uint256 actor) internal returns (bool claimed) {
        vm.prank(s_actor[actor]);
        try s_deployed.dvrFaucet.claim() {
            s_walletDvr[actor] += CLAIM_DVR;
            s_dvrPaid += CLAIM_DVR;
            s_ghostDvr -= CLAIM_DVR;
            claimed = true;
        } catch (bytes memory reason) {
            bytes4 selector = _selector(reason);
            if (
                selector != DriverFaucet.DriverFaucet__ClaimTooSoon.selector
                    && selector != DriverFaucet.DriverFaucet__DailyLimitReached.selector
            ) _bubble(reason);
        }
    }

    function _claimUsdc(uint256 actor) internal returns (bool claimed) {
        vm.prank(s_actor[actor]);
        try s_deployed.usdcFaucet.claim() {
            s_walletUsdc[actor] += CLAIM_USDC;
            claimed = true;
        } catch (bytes memory reason) {
            bytes4 selector = _selector(reason);
            if (
                selector != MockUsdcFaucet.MockUsdcFaucet__ClaimTooSoon.selector
                    && selector != MockUsdcFaucet.MockUsdcFaucet__DailyLimitReached.selector
            ) _bubble(reason);
        }
    }

    function _lock(uint256 actor, uint256 amount) internal {
        uint256 roundId = _round();
        s_walletDvr[actor] -= amount;
        s_lock[actor] += amount;
        address farm = s_choice[roundId][actor];
        if (farm != address(0)) s_tally[roundId][farm] += amount;
        s_ghostDvr += amount;
        vm.prank(s_actor[actor]);
        s_deployed.vote.lock(amount);
    }

    function _unlock(uint256 actor, uint256 amount) internal {
        s_lock[actor] -= amount;
        s_walletDvr[actor] += amount;
        s_ghostDvr -= amount;
        vm.prank(s_actor[actor]);
        s_deployed.vote.unlock(amount);
    }

    function _vote(uint256 actor, address farm) internal returns (bool replaced) {
        uint256 roundId = _round();
        address previous = s_choice[roundId][actor];
        if (previous != farm) {
            if (previous != address(0)) {
                s_tally[roundId][previous] -= s_lock[actor];
                replaced = true;
            }
            s_tally[roundId][farm] += s_lock[actor];
            s_choice[roundId][actor] = farm;
        }
        vm.prank(s_actor[actor]);
        s_deployed.vote.vote(IMockFarm(farm));
    }

    function _skip(uint256 secondsForward) internal {
        vm.prank(s_owner);
        s_clock.advanceTime(secondsForward);
        s_ghostOffset += secondsForward;
    }

    function _keepTie() internal {
        _lock(1, LOCK_FORCED);
        _vote(0, s_farm[DRIFT]);
        _vote(1, s_farm[HIGHWAY]);
        _skip(EPOCH);
        uint256 closed = _round() - 1;
        if (address(s_deployed.vote.leader(closed)) != s_farm[HIGHWAY]) revert ProtocolHandler__TieMissed();
        if (address(s_deployed.vote.winner(closed)) != address(0)) revert ProtocolHandler__TieMissed();
        _harvestFund(false);
        if (s_active2 != DRIFT || address(s_deployed.degenDriver.activeFarm()) != s_farm[DRIFT]) {
            revert ProtocolHandler__TieMissed();
        }
        s_tieKept += 1;
    }

    function _exitCampaign() internal {
        uint256 votedRound = _round();
        _vote(0, s_farm[DRIFT]);
        _exitForced(false);
        s_exit2 += 1;
        _exitForced(true);
        s_exit1 += 1;

        _skip(EPOCH);
        uint256 closed = _round() - 1;
        if (closed != votedRound || s_active2 != NONE || s_tally[closed][s_farm[DRIFT]] == 0) {
            revert ProtocolHandler__IgnoredMissed();
        }
        if (address(s_deployed.degenDriver.activeFarm()) != address(0)) revert ProtocolHandler__IgnoredMissed();
        if (s_deployed.vote.tally(closed, s_farm[DRIFT]) == 0) revert ProtocolHandler__IgnoredMissed();
        _harvestFund(false);
        if (s_active2 != NONE || address(s_deployed.degenDriver.activeFarm()) != address(0)) {
            revert ProtocolHandler__IgnoredMissed();
        }
        if (s_deployed.degenDriver.isStrategy(s_farm[DRIFT]) || !s_deployed.drift.paused()) {
            revert ProtocolHandler__IgnoredMissed();
        }
        s_ignored += 1;
        s_harvestAfterExit += 1;
        _harvestFund(true);
        s_harvestAfterExit += 1;
    }

    function _exitForced(bool fund1) internal {
        uint256 active = fund1 ? s_active1 : s_active2;
        if (active == NONE || s_principal[active] == 0) revert ProtocolHandler__ExitMissed();
        address farm = s_farm[active];
        _exit(fund1);
        if (fund1) {
            if (address(s_deployed.cruiseControl.activeFarm()) != address(0)) revert ProtocolHandler__ExitMissed();
            if (s_deployed.cruiseControl.isStrategy(farm) || !MockFarm(farm).paused()) {
                revert ProtocolHandler__ExitMissed();
            }
        } else if (
            address(s_deployed.degenDriver.activeFarm()) != address(0) || s_deployed.degenDriver.isStrategy(farm)
                || !MockFarm(farm).paused()
        ) {
            revert ProtocolHandler__ExitMissed();
        }
    }

    function _exitExternal(bool fund1) internal {
        uint256 active = fund1 ? s_active1 : s_active2;
        if (active != NONE) {
            _exit(fund1);
            return;
        }
        vm.prank(s_owner);
        if (fund1) {
            try s_deployed.cruiseControl.emergencyWithdraw("exit") {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (_selector(reason) != TreasuryFund.TreasuryFund__NoActiveFarm.selector) _bubble(reason);
            }
        } else {
            try s_deployed.degenDriver.emergencyWithdraw("exit") {
                revert ProtocolHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                if (_selector(reason) != TreasuryFund.TreasuryFund__NoActiveFarm.selector) _bubble(reason);
            }
        }
    }

    function _exit(bool fund1) internal {
        uint256 active = fund1 ? s_active1 : s_active2;
        uint256 amount = s_principal[active];
        s_principal[active] = 0;
        s_accrued[active] = 0;
        if (fund1) {
            s_active1 = NONE;
            s_idle1 += amount;
        } else {
            s_active2 = NONE;
            s_idle2 += amount;
        }
        _delist(active);
        s_exited[s_exitedCount] = s_farm[active];
        s_exitedCount += 1;
        _sync(fund1);
        vm.prank(s_owner);
        if (fund1) s_deployed.cruiseControl.emergencyWithdraw("exit");
        else s_deployed.degenDriver.emergencyWithdraw("exit");
    }

    function _delist(uint256 index) internal {
        uint256 count = s_listCount;
        for (uint256 i = 0; i < count; i++) {
            if (s_list[i] != index) continue;
            for (uint256 j = i; j + 1 < count; j++) {
                s_list[j] = s_list[j + 1];
            }
            s_listCount = count - 1;
            return;
        }
    }

    function _claim(uint256 index) internal returns (uint256 paid) {
        _checkpoint(index);
        uint256 owed = s_accrued[index];
        if (owed == 0) return 0;
        uint256 reserve = s_farmReserve[index];
        paid = owed > reserve ? reserve : owed;
        s_accrued[index] = owed - paid;
        s_farmReserve[index] = reserve - paid;
    }

    function _deposit(uint256 index, uint256 amount) internal {
        _checkpoint(index);
        s_principal[index] += amount;
    }

    function _withdraw(uint256 index, uint256 amount) internal {
        _checkpoint(index);
        s_principal[index] -= amount;
    }

    function _checkpoint(uint256 index) internal {
        uint256 nowTime = _now();
        if (s_principal[index] != 0 && nowTime > s_last[index]) {
            uint256 earned = Math.mulDiv(s_principal[index], s_apr[index] * (nowTime - s_last[index]), BPS * YEAR);
            if (earned != 0) s_accrued[index] += earned;
        }
        s_last[index] = nowTime;
    }

    function _quoteBuy(uint256 amountIn) internal view returns (Quote memory quote) {
        quote.amountIn = amountIn;
        if (amountIn == 0 || s_reserveDvr == 0 || s_reserveUsdc == 0) return quote;
        quote.usdcTax = Math.mulDiv(amountIn, TAX, BPS, Math.Rounding.Ceil);
        if (quote.usdcTax >= amountIn) return quote;
        uint256 toReserve = amountIn - quote.usdcTax;
        quote.amountOut = Math.mulDiv(s_reserveDvr, toReserve, s_reserveUsdc + toReserve);
        if (quote.amountOut == 0 || quote.amountOut >= s_reserveDvr) return quote;
        quote.newReserveDvr = s_reserveDvr - quote.amountOut;
        quote.newReserveUsdc = s_reserveUsdc + toReserve;
        quote.ok = true;
    }

    function _quoteSell(uint256 amountIn) internal view returns (Quote memory quote) {
        quote.amountIn = amountIn;
        if (amountIn == 0 || s_reserveDvr == 0 || s_reserveUsdc == 0) return quote;
        uint256 gross = Math.mulDiv(s_reserveUsdc, amountIn, s_reserveDvr + amountIn);
        if (gross == 0 || gross >= s_reserveUsdc) return quote;
        quote.usdcTax = Math.mulDiv(gross, TAX, BPS, Math.Rounding.Ceil);
        if (quote.usdcTax >= gross) return quote;
        quote.amountOut = gross - quote.usdcTax;
        quote.newReserveDvr = s_reserveDvr + amountIn;
        quote.newReserveUsdc = s_reserveUsdc - gross;
        quote.ok = true;
    }

    function _applyReserves(Quote memory quote) internal {
        uint256 before = s_reserveDvr * s_reserveUsdc;
        uint256 afterProduct = quote.newReserveDvr * quote.newReserveUsdc;
        if (afterProduct < before) revert ProtocolHandler__KDecreased(before, afterProduct);
        s_reserveDvr = quote.newReserveDvr;
        s_reserveUsdc = quote.newReserveUsdc;
        if (quote.usdcTax == 0) return;
        uint256 fund1 = Math.mulDiv(quote.usdcTax, 4_000, BPS);
        uint256 fund2 = Math.mulDiv(quote.usdcTax, 4_000, BPS);
        s_tax1 += fund1;
        s_tax2 += fund2;
        s_tax3 += quote.usdcTax - fund1 - fund2;
    }

    function _chosen(uint256 roundId, uint256 active) internal view returns (uint256) {
        uint256 lead = _leader(roundId);
        if (lead == NONE) return active;
        if (active != NONE && s_tally[roundId][s_farm[active]] == s_tally[roundId][s_farm[lead]]) return active;
        return lead;
    }

    function _leader(uint256 roundId) internal view returns (uint256 best) {
        best = NONE;
        uint256 top = 0;
        uint256 count = s_listCount;
        for (uint256 i = 0; i < count; i++) {
            uint256 index = s_list[i];
            uint256 weight = s_tally[roundId][s_farm[index]];
            if (weight > top) {
                top = weight;
                best = index;
            }
        }
    }

    function _sync(bool fund1) internal {
        uint256 active = fund1 ? s_active1 : s_active2;
        uint256 principal = active == NONE ? 0 : s_principal[active];
        if (fund1) s_value1 = s_idle1 + principal;
        else s_value2 = s_idle2 + principal;
    }

    function _setIdle(bool fund1, uint256 idle) internal {
        if (fund1) s_idle1 = idle;
        else s_idle2 = idle;
    }

    function _move(uint256 payerShare, uint256 payerValue, uint256 receiverShare, uint256 receiverValue)
        internal
        pure
        returns (uint256 amount)
    {
        uint256 owed = receiverShare * payerValue;
        uint256 held = payerShare * receiverValue;
        if (owed <= held) return 0;
        amount = (owed - held) / (payerShare + receiverShare);
    }

    function _round() internal view returns (uint256) {
        return (_now() - s_openedAt) / EPOCH;
    }

    function _now() internal view returns (uint256) {
        return block.timestamp + s_ghostOffset;
    }

    function _swapError(bytes memory reason) internal pure returns (bool) {
        bytes4 selector = _selector(reason);
        return selector == IOfficialPool.OfficialPool__ZeroAmount.selector
            || selector == IOfficialPool.OfficialPool__ZeroOutput.selector
            || selector == IOfficialPool.OfficialPool__InsufficientReserves.selector;
    }

    function _selector(bytes memory reason) internal pure returns (bytes4 selector_) {
        if (reason.length < 4) return bytes4(0);
        assembly {
            selector_ := mload(add(reason, 32))
        }
    }

    function _bubble(bytes memory reason) internal pure {
        assembly {
            revert(add(reason, 32), mload(reason))
        }
    }
}
