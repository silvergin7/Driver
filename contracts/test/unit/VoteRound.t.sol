// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DegenDriver} from "../../src/DegenDriver.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverVote} from "../../src/DriverVote.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../src/TreasuryFund.sol";
import {HaltingDriverClock} from "../mocks/HaltingDriverClock.sol";

contract VoteRoundTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant HUNDRED = 100 ether;
    uint256 internal constant SIXTY = 60 ether;
    uint256 internal constant FORTY = 40 ether;

    MockUSDC internal usdc;
    DriverToken internal token;
    DemoDriverClock internal clock;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    RoundSchedule internal schedule;
    MockFarm internal cruiseFarm;
    MockFarm internal highway;
    MockFarm internal autobahn;
    MockFarm internal drift;
    CruiseControl internal cruise;
    DegenDriver internal degen;
    DriverVote internal vote;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        usdc = new MockUSDC(owner);
        token = new DriverToken(owner);
        clock = new DemoDriverClock(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, 100);
        schedule = new RoundSchedule(clock, 30 days);
        vm.prank(owner);
        splitter.setPool(address(pool));

        cruiseFarm = new MockFarm(usdc, clock, 500, owner);
        highway = new MockFarm(usdc, clock, 4_000, owner);
        autobahn = new MockFarm(usdc, clock, 8_000, owner);
        drift = new MockFarm(usdc, clock, 16_000, owner);
        IMockFarm[] memory cruiseFarms = new IMockFarm[](1);
        cruiseFarms[0] = cruiseFarm;
        cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, cruiseFarms, owner);
        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = highway;
        farms[1] = autobahn;
        farms[2] = drift;
        degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, SHARE_1, SHARE_2, farms, owner);
        vote = new DriverVote(token, schedule, degen);

        vm.startPrank(owner);
        usdc.mint(owner, SHARE_1 + SHARE_2);
        usdc.approve(address(cruise), SHARE_1);
        cruise.supply(SHARE_1);
        cruiseFarm.addDepositor(address(cruise));
        cruise.setStrategy(cruiseFarm);
        cruise.deposit(SHARE_1);
        usdc.approve(address(degen), SHARE_2);
        degen.supply(SHARE_2);
        highway.addDepositor(address(degen));
        autobahn.addDepositor(address(degen));
        drift.addDepositor(address(degen));
        cruise.setFund2(degen);
        degen.setBallot(vote);
        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);
        token.mint(carol, 1_000 ether);
        vm.stopPrank();
    }

    function test_LeaderStaysAfterTheHarvestKeepsTheCurrentFarm() public {
        _lock(alice, HUNDRED);
        _vote(alice, highway);
        _skip(30 days);
        _harvest();

        assertEq(address(degen.activeFarm()), address(highway));
        assertEq(address(vote.leader(0)), address(highway));
        assertEq(address(vote.winner(0)), address(0));
    }

    function test_NobodyVotedReturnsZero() public {
        _skip(30 days);

        assertEq(address(vote.leader(0)), address(0));
        assertEq(address(vote.winner(0)), address(0));
    }

    function test_NobodyVotedKeepsAnActiveFarm() public {
        _elect(highway);
        _skip(30 days);

        assertEq(address(degen.activeFarm()), address(highway));
        assertEq(address(vote.leader(1)), address(0));
        assertEq(address(vote.winner(1)), address(0));
    }

    function test_CurrentLeaderKeepsTheFarm() public {
        _elect(highway);
        _vote(alice, highway);
        _skip(30 days);

        assertEq(address(vote.leader(1)), address(highway));
        assertEq(address(vote.winner(1)), address(0));
    }

    function test_UniqueLeaderReplacesAnotherFarm() public {
        _elect(autobahn);
        _vote(alice, highway);
        _skip(30 days);

        assertEq(address(vote.leader(1)), address(highway));
        assertEq(address(vote.winner(1)), address(highway));
    }

    function test_TieSkipsTheCurrentFarm() public {
        _elect(drift);
        _lock(bob, HUNDRED);
        _vote(alice, highway);
        _vote(bob, autobahn);
        _skip(30 days);

        assertEq(address(vote.leader(1)), address(highway));
        assertEq(address(vote.winner(1)), address(highway));
    }

    function test_TieThatIncludesTheCurrentFarmKeepsIt() public {
        _elect(highway);
        _lock(bob, HUNDRED);
        _vote(alice, highway);
        _vote(bob, autobahn);
        _skip(30 days);

        assertEq(address(vote.leader(1)), address(highway));
        assertEq(address(vote.winner(1)), address(0));
    }

    function test_ThreeWayTieWithNoActiveFarmPicksTheEarliest() public {
        _lock(alice, HUNDRED);
        _lock(bob, HUNDRED);
        _lock(carol, HUNDRED);
        _vote(alice, highway);
        _vote(bob, autobahn);
        _vote(carol, drift);
        _skip(30 days);

        assertEq(address(degen.activeFarm()), address(0));
        assertEq(address(vote.leader(0)), address(highway));
        assertEq(address(vote.winner(0)), address(highway));
    }

    function test_ThreeWayTieKeepsTheCurrentFarm() public {
        _elect(drift);
        _lock(bob, HUNDRED);
        _lock(carol, HUNDRED);
        _vote(alice, highway);
        _vote(bob, autobahn);
        _vote(carol, drift);
        _skip(30 days);

        assertEq(address(vote.leader(1)), address(highway));
        assertEq(address(vote.winner(1)), address(0));
    }

    function test_VotesOnlyOnADelistedFarmReturnZero() public {
        _elect(drift);
        _vote(alice, drift);
        _skip(30 days);
        _exit();

        assertFalse(degen.isStrategy(address(drift)));
        assertEq(vote.tally(1, address(drift)), HUNDRED);
        assertEq(address(vote.leader(1)), address(0));
        assertEq(address(vote.winner(1)), address(0));
    }

    function test_DelistedLeaderLeavesTheNextFarm() public {
        _elect(drift);
        _lock(bob, SIXTY);
        _lock(carol, FORTY);
        _vote(alice, drift);
        _vote(bob, autobahn);
        _vote(carol, highway);
        _skip(30 days);
        _exit();

        assertEq(address(vote.leader(1)), address(autobahn));
        assertEq(address(vote.winner(1)), address(autobahn));
    }

    function test_ExitingTheFirstFarmKeepsRegistrationOrder() public {
        _elect(highway);
        _lock(bob, HUNDRED);
        _lock(carol, HUNDRED);
        _vote(alice, highway);
        _vote(bob, autobahn);
        _vote(carol, drift);
        _skip(30 days);
        _exit();

        assertEq(degen.strategyCount(), 2);
        assertEq(address(degen.strategyAt(0)), address(autobahn));
        assertEq(address(degen.strategyAt(1)), address(drift));
        assertEq(address(vote.leader(1)), address(autobahn));
        assertEq(address(vote.winner(1)), address(autobahn));
    }

    function test_AllThreeFarmsDelistedRejectEveryVote() public {
        _elect(highway);
        _exit();
        _vote(alice, autobahn);
        _skip(30 days);
        _harvest();
        _exit();
        _vote(alice, drift);
        _skip(30 days);
        _harvest();
        _exit();

        assertEq(degen.strategyCount(), 0);
        assertEq(address(degen.activeFarm()), address(0));
        assertEq(address(vote.leader(0)), address(0));
        assertEq(address(vote.winner(0)), address(0));
        assertEq(address(vote.leader(1)), address(0));
        assertEq(address(vote.winner(1)), address(0));
        assertEq(address(vote.leader(2)), address(0));
        assertEq(address(vote.winner(2)), address(0));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__StrategyNotAllowed.selector, address(highway)));
        vote.vote(highway);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__StrategyNotAllowed.selector, address(autobahn)));
        vote.vote(autobahn);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__StrategyNotAllowed.selector, address(drift)));
        vote.vote(drift);
    }

    function test_RevoteRemovesWeightFromADelistedFarm() public {
        _elect(drift);
        _vote(alice, drift);
        _exit();

        vm.prank(alice);
        vote.vote(autobahn);

        assertEq(vote.tally(schedule.currentRound(), address(drift)), 0);
        assertEq(vote.tally(schedule.currentRound(), address(autobahn)), HUNDRED);
        assertEq(vote.voteOf(schedule.currentRound(), alice), address(autobahn));
    }

    function test_OpenRoundIsProvisionalAndHarvestReverts() public {
        _lock(alice, HUNDRED);
        _vote(alice, highway);

        vm.prank(owner);
        vm.expectRevert(RoundSchedule.RoundSchedule__NoClosedRound.selector);
        degen.harvest(0);
        assertEq(address(vote.leader(0)), address(highway));
        assertEq(address(vote.winner(0)), address(highway));

        _lock(bob, HUNDRED + HUNDRED);
        _vote(bob, drift);

        assertEq(address(vote.leader(0)), address(drift));
        assertEq(address(vote.winner(0)), address(drift));
    }

    function test_HaltedClockDoesNotRevertTheClosedResult() public {
        HaltingDriverClock halting = new HaltingDriverClock();
        halting.setTime(1_000_000);
        RoundSchedule timed = new RoundSchedule(halting, 1 days);
        MockFarm timedHighway = new MockFarm(usdc, halting, 4_000, owner);
        MockFarm timedAutobahn = new MockFarm(usdc, halting, 8_000, owner);
        MockFarm timedDrift = new MockFarm(usdc, halting, 16_000, owner);
        MockFarm timedCruiseFarm = new MockFarm(usdc, halting, 500, owner);
        IMockFarm[] memory cruiseFarms = new IMockFarm[](1);
        cruiseFarms[0] = timedCruiseFarm;
        CruiseControl timedCruise =
            new CruiseControl(usdc, halting, timed, splitter, pool, SHARE_1, SHARE_2, cruiseFarms, owner);
        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = timedHighway;
        farms[1] = timedAutobahn;
        farms[2] = timedDrift;
        DegenDriver timedDegen =
            new DegenDriver(usdc, halting, timed, splitter, pool, timedCruise, SHARE_1, SHARE_2, farms, owner);
        DriverVote timedVote = new DriverVote(token, timed, timedDegen);

        vm.prank(owner);
        token.mint(alice, HUNDRED);
        _lockOn(timedVote, alice, HUNDRED);
        vm.prank(alice);
        timedVote.vote(timedHighway);
        halting.setTime(1_000_000 + 1 days);
        halting.halt();

        (bool ok, bytes memory data) = address(timed).call(abi.encodeWithSignature("currentRound()"));
        assertFalse(ok);
        assertEq(bytes4(data), HaltingDriverClock.HaltingDriverClock__Halted.selector);
        assertEq(address(timedVote.leader(0)), address(timedHighway));
        assertEq(address(timedVote.winner(0)), address(timedHighway));
        assertEq(address(timedVote.leader(99)), address(0));
        assertEq(address(timedVote.winner(99)), address(0));
    }

    function test_TwoClosedRoundsApplyTheLatest() public {
        _lock(alice, HUNDRED);
        _vote(alice, highway);
        _skip(30 days);
        _vote(alice, drift);
        _skip(30 days);
        _harvest();

        (bool harvested, uint256 roundId) = degen.lastHarvestedRound();
        assertTrue(harvested);
        assertEq(roundId, 1);
        assertEq(address(degen.activeFarm()), address(drift));
        assertEq(vote.tally(0, address(highway)), HUNDRED);
        assertEq(address(vote.leader(0)), address(highway));
        assertEq(address(vote.winner(0)), address(highway));
        assertEq(address(vote.leader(1)), address(drift));
        assertEq(address(vote.winner(1)), address(0));
    }

    function test_HarvestAppliesTheVote() public {
        _lock(alice, HUNDRED);
        _vote(alice, highway);
        _skip(30 days);

        vm.expectEmit(true, true, false, true, address(degen));
        emit TreasuryFund.StrategySet(address(0), address(highway), 0, 0);
        vm.expectEmit(true, false, false, true, address(degen));
        emit TreasuryFund.CapitalDeployed(address(highway), SHARE_2, 0);
        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.Rebalanced(0, SHARE_1, SHARE_2, 0);
        vm.expectEmit(true, false, false, true, address(degen));
        emit TreasuryFund.Harvested(0, 0, 0, 0, 0, 0, 0);
        vm.recordLogs();
        _harvest();

        assertFalse(_saw(DegenDriver.WinnerIgnored.selector));
        assertEq(address(degen.activeFarm()), address(highway));
        assertEq(degen.idle(), 0);
        assertEq(degen.principal(), SHARE_2);
        assertEq(degen.dvrBoughtBack(), 0);
        assertEq(cruise.value(), SHARE_1);
        assertEq(degen.value(), SHARE_2);
    }

    function test_ExitBetweenCloseAndHarvestAppliesTheNextFarm() public {
        _elect(drift);
        _lock(bob, SIXTY);
        _vote(alice, drift);
        _vote(bob, autobahn);
        _skip(30 days);
        _exit();

        assertEq(address(degen.activeFarm()), address(0));
        assertEq(address(vote.winner(1)), address(autobahn));
        _harvest();

        assertEq(address(degen.activeFarm()), address(autobahn));
        assertEq(degen.lastHarvest().roundId, 1);
    }

    function _elect(MockFarm farm) private {
        _lock(alice, HUNDRED);
        _vote(alice, farm);
        _skip(30 days);
        _harvest();
    }

    function _harvest() private {
        vm.prank(owner);
        degen.harvest(0);
    }

    function _exit() private {
        vm.prank(owner);
        degen.emergencyWithdraw("exit");
    }

    function _lock(address holder, uint256 amount) private {
        _lockOn(vote, holder, amount);
    }

    function _lockOn(DriverVote vote_, address holder, uint256 amount) private {
        vm.startPrank(holder);
        token.approve(address(vote_), amount);
        vote_.lock(amount);
        vm.stopPrank();
    }

    function _vote(address holder, MockFarm farm) private {
        vm.prank(holder);
        vote.vote(farm);
    }

    function _skip(uint256 seconds_) private {
        vm.prank(owner);
        clock.advanceTime(seconds_);
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
