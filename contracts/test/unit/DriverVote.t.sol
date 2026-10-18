// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {ITreasuryFund} from "../../src/interfaces/ITreasuryFund.sol";
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

contract DriverVoteTest is Test, IERC20Errors {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant HUNDRED = 100 ether;
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
        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);
        vm.stopPrank();
    }

    function test_ConstructorStoresTheTokenScheduleAndFund() public view {
        assertEq(address(vote.i_token()), address(token));
        assertEq(address(vote.i_schedule()), address(schedule));
        assertEq(address(vote.i_fund()), address(degen));
        assertEq(vote.counted(), 0);
        assertEq(token.balanceOf(address(vote)), 0);
    }

    function test_RevertWhen_TokenIsZero() public {
        vm.expectRevert(DriverVote.DriverVote__ZeroAddress.selector);
        new DriverVote(DriverToken(address(0)), schedule, degen);
    }

    function test_RevertWhen_ScheduleIsZero() public {
        vm.expectRevert(DriverVote.DriverVote__ZeroAddress.selector);
        new DriverVote(token, RoundSchedule(address(0)), degen);
    }

    function test_RevertWhen_FundIsZero() public {
        vm.expectRevert(DriverVote.DriverVote__ZeroAddress.selector);
        new DriverVote(token, schedule, ITreasuryFund(address(0)));
    }

    function test_RevertWhen_ScheduleDoesNotMatchTheFund() public {
        RoundSchedule other = new RoundSchedule(clock, 30 days);

        vm.expectRevert(DriverVote.DriverVote__ScheduleMismatch.selector);
        new DriverVote(token, other, degen);
    }

    function test_RevertWhen_FundIsNotFund2() public {
        vm.expectRevert(DriverVote.DriverVote__NotFund2.selector);
        new DriverVote(token, schedule, cruise);
    }

    function test_LockPullsDvrAndCountsIt() public {
        vm.startPrank(alice);
        token.approve(address(vote), HUNDRED);
        vm.expectEmit(true, false, false, true, address(vote));
        emit DriverVote.Locked(alice, HUNDRED, HUNDRED);
        vote.lock(HUNDRED);
        vm.stopPrank();

        assertEq(vote.locked(alice), HUNDRED);
        assertEq(vote.counted(), HUNDRED);
        assertEq(token.balanceOf(address(vote)), HUNDRED);
        assertEq(token.balanceOf(alice), 1_000 ether - HUNDRED);
        assertEq(token.allowance(alice, address(vote)), 0);
        assertEq(vote.tally(0, address(highway)), 0);
    }

    function test_SecondLockAddsToTheSameBalance() public {
        _lock(alice, HUNDRED);

        vm.startPrank(alice);
        token.approve(address(vote), FORTY);
        vm.expectEmit(true, false, false, true, address(vote));
        emit DriverVote.Locked(alice, FORTY, HUNDRED + FORTY);
        vote.lock(FORTY);
        vm.stopPrank();

        assertEq(vote.locked(alice), HUNDRED + FORTY);
        assertEq(vote.counted(), HUNDRED + FORTY);
        assertEq(token.balanceOf(address(vote)), HUNDRED + FORTY);
    }

    function test_UnlockReturnsASlice() public {
        _lock(alice, HUNDRED);

        vm.expectEmit(true, false, false, true, address(vote));
        emit DriverVote.Unlocked(alice, FORTY, HUNDRED - FORTY);
        vm.prank(alice);
        vote.unlock(FORTY);

        assertEq(vote.locked(alice), HUNDRED - FORTY);
        assertEq(vote.counted(), HUNDRED - FORTY);
        assertEq(token.balanceOf(alice), 1_000 ether - HUNDRED + FORTY);
        assertEq(token.balanceOf(address(vote)), HUNDRED - FORTY);
    }

    function test_RevertWhen_LockAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(DriverVote.DriverVote__ZeroAmount.selector);
        vote.lock(0);

        assertEq(vote.counted(), 0);
    }

    function test_RevertWhen_UnlockAmountIsZero() public {
        _lock(alice, HUNDRED);

        vm.prank(alice);
        vm.expectRevert(DriverVote.DriverVote__ZeroAmount.selector);
        vote.unlock(0);

        assertEq(vote.locked(alice), HUNDRED);
    }

    function test_RevertWhen_UnlockExceedsTheLock() public {
        _lock(alice, HUNDRED);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__InsufficientLock.selector, HUNDRED, HUNDRED + 1));
        vote.unlock(HUNDRED + 1);

        assertEq(vote.locked(alice), HUNDRED);
        assertEq(token.balanceOf(address(vote)), HUNDRED);
    }

    function test_RevertWhen_LockExceedsBalance() public {
        vm.prank(alice);
        token.approve(address(vote), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, alice, 1_000 ether, 1_001 ether));
        vote.lock(1_001 ether);

        assertEq(vote.counted(), 0);
    }

    function test_RevertWhen_LockIsNotApproved() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(vote), 0, HUNDRED));
        vote.lock(HUNDRED);

        assertEq(vote.counted(), 0);
    }

    function test_DirectTransferIsNotALock() public {
        vm.prank(owner);
        token.mint(address(vote), 7 ether);

        assertEq(token.balanceOf(address(vote)), 7 ether);
        assertEq(vote.counted(), 0);
        assertEq(vote.locked(alice), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__InsufficientLock.selector, 0, 1));
        vote.unlock(1);

        assertEq(token.balanceOf(address(vote)), 7 ether);
    }

    function test_VoteRecordsTheFarmAndTheWeight() public {
        _lock(alice, HUNDRED);

        vm.expectEmit(true, true, true, true, address(vote));
        emit DriverVote.VoteCast(alice, 0, address(highway), HUNDRED);
        vm.prank(alice);
        vote.vote(highway);

        assertEq(vote.voteOf(0, alice), address(highway));
        assertEq(vote.tally(0, address(highway)), HUNDRED);
        assertEq(vote.openTally(address(highway)), HUNDRED);
        assertEq(vote.tally(0, address(autobahn)), 0);
    }

    function test_LockAfterAVoteAddsTheNewAmount() public {
        _lock(alice, HUNDRED);
        vm.prank(alice);
        vote.vote(highway);

        _lock(alice, FORTY);

        assertEq(vote.locked(alice), HUNDRED + FORTY);
        assertEq(vote.tally(0, address(highway)), HUNDRED + FORTY);
        assertEq(vote.voteOf(0, alice), address(highway));
    }

    function test_RevoteMovesTheWeight() public {
        _lock(alice, HUNDRED);
        vm.prank(alice);
        vote.vote(highway);
        _lock(alice, FORTY);

        vm.expectEmit(true, true, true, true, address(vote));
        emit DriverVote.VoteCast(alice, 0, address(autobahn), HUNDRED + FORTY);
        vm.prank(alice);
        vote.vote(autobahn);

        assertEq(vote.voteOf(0, alice), address(autobahn));
        assertEq(vote.tally(0, address(highway)), 0);
        assertEq(vote.tally(0, address(autobahn)), HUNDRED + FORTY);
    }

    function test_RevoteToTheSameFarmKeepsTheTally() public {
        _lock(alice, HUNDRED);
        vm.prank(alice);
        vote.vote(highway);
        _lock(alice, FORTY);

        vm.expectEmit(true, true, true, true, address(vote));
        emit DriverVote.VoteCast(alice, 0, address(highway), HUNDRED + FORTY);
        vm.prank(alice);
        vote.vote(highway);

        assertEq(vote.tally(0, address(highway)), HUNDRED + FORTY);
        assertEq(vote.voteOf(0, alice), address(highway));
    }

    function test_TwoHoldersSumOnTheSameFarm() public {
        _lock(alice, HUNDRED);
        _lock(bob, FORTY);
        vm.prank(alice);
        vote.vote(highway);
        vm.prank(bob);
        vote.vote(highway);

        assertEq(vote.tally(0, address(highway)), HUNDRED + FORTY);
        assertEq(vote.counted(), HUNDRED + FORTY);
    }

    function test_OneWeiVotesWithWeightOne() public {
        _lock(alice, 1);

        vm.expectEmit(true, true, true, true, address(vote));
        emit DriverVote.VoteCast(alice, 0, address(highway), 1);
        vm.prank(alice);
        vote.vote(highway);

        assertEq(vote.locked(alice), 1);
        assertEq(vote.tally(0, address(highway)), 1);
    }

    function test_ClosedRoundTallyStaysPut() public {
        _lock(alice, HUNDRED);
        vm.prank(alice);
        vote.vote(highway);
        _skip(30 days);

        _lock(alice, FORTY);
        vm.prank(alice);
        vote.unlock(50 ether);
        vm.prank(alice);
        vote.vote(autobahn);

        assertEq(vote.tally(0, address(highway)), HUNDRED);
        assertEq(vote.tally(0, address(autobahn)), 0);
        assertEq(vote.voteOf(0, alice), address(highway));
        assertEq(vote.voteOf(1, alice), address(autobahn));
        assertEq(vote.tally(1, address(autobahn)), HUNDRED + FORTY - 50 ether);
        assertEq(vote.locked(alice), HUNDRED + FORTY - 50 ether);
        assertEq(schedule.currentRound(), 1);
    }

    function test_UnlockIsBlockedUntilTheRoundEnds() public {
        _lock(alice, HUNDRED);
        vm.prank(alice);
        vote.vote(highway);
        uint256 end = schedule.roundEnd(0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__Voted.selector, 0, end));
        vote.unlock(1);

        _skip(30 days - 1);
        assertEq(schedule.currentRound(), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__Voted.selector, 0, end));
        vote.unlock(1);

        _skip(1);
        assertEq(clock.currentTime(), end);
        assertEq(schedule.currentRound(), 1);

        vm.expectEmit(true, false, false, true, address(vote));
        emit DriverVote.Unlocked(alice, FORTY, HUNDRED - FORTY);
        vm.prank(alice);
        vote.unlock(FORTY);

        assertEq(vote.tally(0, address(highway)), HUNDRED);
        assertEq(vote.locked(alice), HUNDRED - FORTY);
    }

    function test_RevertWhen_VoteHasNoLock() public {
        vm.prank(alice);
        vm.expectRevert(DriverVote.DriverVote__NothingLocked.selector);
        vote.vote(highway);

        assertEq(vote.voteOf(0, alice), address(0));
    }

    function test_RevertWhen_VoteFarmIsZero() public {
        _lock(alice, HUNDRED);

        vm.prank(alice);
        vm.expectRevert(DriverVote.DriverVote__ZeroAddress.selector);
        vote.vote(IMockFarm(address(0)));
    }

    function test_RevertWhen_FarmIsNotListed() public {
        _lock(alice, HUNDRED);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__StrategyNotAllowed.selector, address(cruiseFarm)));
        vote.vote(cruiseFarm);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__StrategyNotAllowed.selector, address(degen)));
        vote.vote(IMockFarm(address(degen)));

        assertEq(vote.voteOf(0, alice), address(0));
        assertEq(vote.tally(0, address(cruiseFarm)), 0);
    }

    function test_UnlockStatusBeforeAndAfterAVote() public {
        (bool emptyCan, uint256 emptyAt) = vote.unlockStatus(alice);
        assertFalse(emptyCan);
        assertEq(emptyAt, 0);

        _lock(alice, HUNDRED);
        (bool openCan, uint256 openAt) = vote.unlockStatus(alice);
        assertTrue(openCan);
        assertEq(openAt, clock.currentTime());

        vm.prank(alice);
        vote.vote(highway);
        (bool votedCan, uint256 votedAt) = vote.unlockStatus(alice);
        assertFalse(votedCan);
        assertEq(votedAt, schedule.roundEnd(0));
        assertEq(vote.openRoundEnd(), schedule.roundEnd(0));
    }

    function _lock(address holder, uint256 amount) private {
        vm.startPrank(holder);
        token.approve(address(vote), amount);
        vote.lock(amount);
        vm.stopPrank();
    }

    function _skip(uint256 seconds_) private {
        vm.prank(owner);
        clock.advanceTime(seconds_);
    }
}
