// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IMockFarm} from "../../../src/interfaces/IMockFarm.sol";
import {CruiseControl} from "../../../src/CruiseControl.sol";
import {DegenDriver} from "../../../src/DegenDriver.sol";
import {DemoDriverClock} from "../../../src/DemoDriverClock.sol";
import {DriverToken} from "../../../src/DriverToken.sol";
import {DriverVote} from "../../../src/DriverVote.sol";
import {MockFarm} from "../../../src/MockFarm.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";
import {OfficialPool} from "../../../src/OfficialPool.sol";
import {RoundSchedule} from "../../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../../src/TaxSplitter.sol";

contract DriverVoteHandler is Test {
    uint256 internal constant ACTORS = 3;
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant EPOCH = 30 days;
    uint256 internal constant ACTOR_BALANCE = 200_000 ether;
    uint256 internal constant DONATION = 50_000 ether;
    uint256 internal constant HUNDRED = 100 ether;
    uint256 internal constant FORTY = 40 ether;

    MockUSDC public s_usdc;
    DriverToken public s_token;
    DemoDriverClock public s_clock;
    TaxSplitter public s_splitter;
    OfficialPool public s_pool;
    RoundSchedule public s_schedule;
    MockFarm public s_cruiseFarm;
    MockFarm public s_highway;
    MockFarm public s_autobahn;
    MockFarm public s_drift;
    CruiseControl public s_cruise;
    DegenDriver public s_degen;
    DriverVote public s_vote;

    address[3] public s_actor;
    address[3] public s_farm;
    uint256[3] public s_lock;
    address[3] public s_choice;
    uint256[3] public s_lockedAtVote;
    mapping(uint256 roundId => mapping(address farm => uint256 weight)) public s_ghostTally;

    uint256 public s_round;
    uint256 public s_direct;
    uint256 public s_lockAfterVote;
    uint256 public s_revoted;
    uint256 public s_afterClose;
    uint256 public s_boundary;
    uint256 public s_switched;
    uint256 public s_kept;
    uint256 public s_mainExit;
    uint256 public s_afterDelist;

    uint256 internal s_advanced;
    uint256 internal s_donationLeft;
    bool internal s_ran;

    error DriverVoteHandler__UnexpectedSuccess();
    error DriverVoteHandler__UnexpectedRevert(bytes reason);
    error DriverVoteHandler__TransferFailed();
    error DriverVoteHandler__HarvestMissed();
    error DriverVoteHandler__KeepCurrentMissed();
    error DriverVoteHandler__ExitMissed();
    error DriverVoteHandler__ListedLeaderMissed();

    constructor() {
        s_usdc = new MockUSDC(address(this));
        s_token = new DriverToken(address(this));
        s_clock = new DemoDriverClock(address(this));
        s_splitter = new TaxSplitter(s_usdc, address(this));
        s_pool = new OfficialPool(s_token, s_usdc, s_splitter, address(this), 100);
        s_splitter.setPool(address(s_pool));
        s_schedule = new RoundSchedule(s_clock, EPOCH);

        s_cruiseFarm = new MockFarm(s_usdc, s_clock, 500, address(this));
        s_highway = new MockFarm(s_usdc, s_clock, 4_000, address(this));
        s_autobahn = new MockFarm(s_usdc, s_clock, 8_000, address(this));
        s_drift = new MockFarm(s_usdc, s_clock, 16_000, address(this));
        IMockFarm[] memory cruiseFarms = new IMockFarm[](1);
        cruiseFarms[0] = s_cruiseFarm;
        s_cruise = new CruiseControl(
            s_usdc, s_clock, s_schedule, s_splitter, s_pool, SHARE_1, SHARE_2, cruiseFarms, address(this)
        );
        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = s_highway;
        farms[1] = s_autobahn;
        farms[2] = s_drift;
        s_degen = new DegenDriver(
            s_usdc, s_clock, s_schedule, s_splitter, s_pool, s_cruise, SHARE_1, SHARE_2, farms, address(this)
        );
        s_vote = new DriverVote(s_token, s_schedule, s_degen);
        s_highway.addDepositor(address(s_degen));
        s_autobahn.addDepositor(address(s_degen));
        s_drift.addDepositor(address(s_degen));
        s_usdc.mint(address(this), SHARE_1 + SHARE_2);
        s_usdc.approve(address(s_cruise), SHARE_1);
        s_cruise.supply(SHARE_1);
        s_usdc.approve(address(s_degen), SHARE_2);
        s_degen.supply(SHARE_2);
        s_cruise.setFund2(s_degen);
        s_degen.setBallot(s_vote);

        s_farm[0] = address(s_highway);
        s_farm[1] = address(s_autobahn);
        s_farm[2] = address(s_drift);
        for (uint256 i = 0; i < ACTORS; i++) {
            address actor = makeAddr(string.concat("voter", vm.toString(i)));
            s_actor[i] = actor;
            s_token.mint(actor, ACTOR_BALANCE);
            vm.prank(actor);
            s_token.approve(address(s_vote), type(uint256).max);
        }
        s_token.mint(address(this), DONATION);
        s_donationLeft = DONATION;
    }

    function lock(uint256 actorSeed, uint256 amount) external {
        _campaign();
        uint256 index = bound(actorSeed, 0, ACTORS - 1);
        uint256 balance = s_token.balanceOf(s_actor[index]);
        if (balance == 0) {
            return;
        }
        _lockActor(index, bound(amount, 1, balance));
    }

    function unlock(uint256 actorSeed, uint256 amount) external {
        _campaign();
        uint256 index = bound(actorSeed, 0, ACTORS - 1);
        uint256 locked_ = s_lock[index];
        if (locked_ == 0) {
            return;
        }
        _unlockActor(index, bound(amount, 1, locked_));
    }

    function vote(uint256 actorSeed, uint256 farmSeed) external {
        _campaign();
        uint256 index = bound(actorSeed, 0, ACTORS - 1);
        _voteActor(index, s_farm[bound(farmSeed, 0, 2)]);
    }

    function advance(uint256 secondsForward) external {
        _campaign();
        _advance(bound(secondsForward, 1, 365 days));
    }

    function donate(uint256 amount) external {
        _campaign();
        if (s_donationLeft == 0) {
            return;
        }
        uint256 gift = bound(amount, 1, s_donationLeft);
        s_donationLeft -= gift;
        s_direct += gift;
        if (!s_token.transfer(address(s_vote), gift)) {
            revert DriverVoteHandler__TransferFailed();
        }
    }

    function harvest() external {
        _campaign();
        _harvestReady();
    }

    function exitActive() external {
        _campaign();
        if (address(s_degen.activeFarm()) == address(0)) {
            return;
        }
        s_degen.emergencyWithdraw("exit");
    }

    function expectedLeader(uint256 roundId) public view returns (address leader_) {
        uint256 count = s_degen.strategyCount();
        uint256 top = 0;
        address best = address(0);
        for (uint256 i = 0; i < count; i++) {
            address farm = address(s_degen.strategyAt(i));
            uint256 weight = s_ghostTally[roundId][farm];
            if (weight > top) {
                top = weight;
                best = farm;
            }
        }
        return best;
    }

    function expectedWinner(uint256 roundId) public view returns (address winner_) {
        address lead = expectedLeader(roundId);
        if (lead == address(0)) {
            return address(0);
        }
        address active = address(s_degen.activeFarm());
        if (active != address(0) && s_ghostTally[roundId][active] == s_ghostTally[roundId][lead]) {
            return address(0);
        }
        return lead;
    }

    function _campaign() private {
        if (s_ran) {
            return;
        }
        s_ran = true;
        _lockActor(0, HUNDRED);
        _voteActor(0, s_farm[0]);
        _lockActor(0, FORTY);
        s_lockAfterVote += 1;
        _lockActor(0, FORTY);
        _voteActor(0, s_farm[1]);
        s_revoted += 1;
        _advance(EPOCH);
        _unlockActor(0, FORTY);
        s_boundary += 1;
        _voteActor(0, s_farm[0]);
        s_afterClose += 1;
        if (!_harvestReady()) {
            revert DriverVoteHandler__HarvestMissed();
        }
        s_switched += 1;
        if (address(s_degen.activeFarm()) != s_farm[1] || address(s_vote.leader(0)) != s_farm[1]) {
            revert DriverVoteHandler__KeepCurrentMissed();
        }
        s_kept += 1;
        _advance(EPOCH);
        if (address(s_degen.activeFarm()) == address(0)) {
            revert DriverVoteHandler__ExitMissed();
        }
        s_degen.emergencyWithdraw("exit");
        s_mainExit += 1;
        uint256 closedRound = s_round - 1;
        address lead = address(s_vote.leader(closedRound));
        if (lead == address(0) || !s_degen.isStrategy(lead)) {
            revert DriverVoteHandler__ListedLeaderMissed();
        }
        s_afterDelist += 1;
        _voteActor(0, s_farm[0]);
        _advance(EPOCH);
        if (!_harvestReady()) {
            revert DriverVoteHandler__HarvestMissed();
        }
        uint256 latest = s_round - 1;
        if (address(s_degen.activeFarm()) != s_farm[0] || address(s_vote.leader(latest)) != s_farm[0]) {
            revert DriverVoteHandler__KeepCurrentMissed();
        }
    }

    function _lockActor(uint256 index, uint256 amount) private {
        address farm = s_choice[index];
        s_lock[index] += amount;
        if (farm != address(0)) {
            s_ghostTally[s_round][farm] += amount;
        }
        vm.prank(s_actor[index]);
        s_vote.lock(amount);
    }

    function _unlockActor(uint256 index, uint256 amount) private {
        address actor = s_actor[index];
        if (s_choice[index] != address(0)) {
            vm.prank(actor);
            try s_vote.unlock(amount) {
                revert DriverVoteHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                _requireSelector(reason, DriverVote.DriverVote__Voted.selector);
            }
            return;
        }
        s_lock[index] -= amount;
        vm.prank(actor);
        s_vote.unlock(amount);
    }

    function _voteActor(uint256 index, address farm) private {
        address actor = s_actor[index];
        if (!s_degen.isStrategy(farm)) {
            vm.prank(actor);
            try s_vote.vote(IMockFarm(farm)) {
                revert DriverVoteHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                _requireSelector(reason, DriverVote.DriverVote__StrategyNotAllowed.selector);
            }
            return;
        }
        uint256 weight = s_lock[index];
        if (weight == 0) {
            vm.prank(actor);
            try s_vote.vote(IMockFarm(farm)) {
                revert DriverVoteHandler__UnexpectedSuccess();
            } catch (bytes memory reason) {
                _requireSelector(reason, DriverVote.DriverVote__NothingLocked.selector);
            }
            return;
        }
        address previous = s_choice[index];
        if (previous != farm) {
            if (previous != address(0)) {
                s_ghostTally[s_round][previous] -= weight;
            }
            s_ghostTally[s_round][farm] += weight;
            s_choice[index] = farm;
        }
        s_lockedAtVote[index] = weight;
        vm.prank(actor);
        s_vote.vote(IMockFarm(farm));
    }

    function _advance(uint256 secondsForward) private {
        s_clock.advanceTime(secondsForward);
        s_advanced += secondsForward;
        uint256 roundId = s_advanced / EPOCH;
        if (roundId == s_round) {
            return;
        }
        s_round = roundId;
        for (uint256 i = 0; i < ACTORS; i++) {
            s_choice[i] = address(0);
            s_lockedAtVote[i] = 0;
        }
    }

    function _harvestReady() private returns (bool switched_) {
        (bool ready, uint256 roundId) = s_degen.harvestableRound();
        if (!ready) {
            return false;
        }
        address activeBefore = address(s_degen.activeFarm());
        s_degen.harvest(roundId);
        address activeAfter = address(s_degen.activeFarm());
        return activeAfter != address(0) && activeAfter != activeBefore;
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector_) {
        if (reason.length < 4) {
            return bytes4(0);
        }
        assembly {
            selector_ := mload(add(reason, 32))
        }
    }

    function _requireSelector(bytes memory reason, bytes4 expected) private pure {
        if (_selector(reason) != expected) {
            revert DriverVoteHandler__UnexpectedRevert(reason);
        }
    }
}
