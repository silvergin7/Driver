// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {IOfficialPool} from "../../src/interfaces/IOfficialPool.sol";
import {ITreasuryFund} from "../../src/interfaces/ITreasuryFund.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DegenDriver} from "../../src/DegenDriver.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../src/TreasuryFund.sol";
import {MappedBallot} from "../mocks/HarvestMocks.sol";
import {HaltingDriverClock} from "../mocks/HaltingDriverClock.sol";

contract EmergencyWithdrawTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;
    uint256 internal constant CRUISE_PRINCIPAL = 15_000 * 10 ** 6;
    uint256 internal constant CRUISE_30_DAYS = 61_643_835;
    uint256 internal constant COMPOUND = 30_821_918;
    uint256 internal constant BUYBACK = 30_821_917;
    uint256 internal constant TOP_UP = 3_750_000_000;
    uint256 internal constant FUND_1_AFTER_TOP_UP = 11_250_000_000;
    uint256 internal constant DRIFT_REWARDS = 657_534_246;
    uint256 internal constant DRIFT_COMPOUND = 328_767_123;
    uint256 internal constant DRIFT_BUYBACK = 328_767_123;
    uint256 internal constant DRIFT_BEFORE = 5_328_767_123;
    uint256 internal constant DRIFT_MOVED = 246_575_342;
    uint256 internal constant DRIFT_FUND1 = 15_246_575_342;
    uint256 internal constant DRIFT_FUND2 = 5_082_191_781;
    uint256 internal constant DRIFT_SUM = 20_328_767_123;
    uint256 internal constant RESERVE = 1_000 * 10 ** 6;

    MockUSDC internal usdc;
    DriverToken internal token;
    DemoDriverClock internal clock;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    RoundSchedule internal schedule;
    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC(owner);
        token = new DriverToken(owner);
        clock = new DemoDriverClock(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, 100);
        schedule = new RoundSchedule(clock, 30 days);
        vm.startPrank(owner);
        splitter.setPool(address(pool));
        token.mint(owner, SEED_DVR);
        usdc.mint(owner, 50_000_000 * 10 ** 6);
        token.approve(address(pool), SEED_DVR);
        usdc.approve(address(pool), SEED_USDC);
        pool.addLiquidity(SEED_DVR, SEED_USDC);
        vm.stopPrank();
    }

    function test_ExitReturnsPrincipalToTheFund() public {
        (CruiseControl cruise, MockFarm farm) = _cruiseReady(500);
        uint256 ownerBefore = usdc.balanceOf(owner);
        uint256 valueBefore = cruise.value();

        vm.expectEmit(true, true, false, true, address(cruise));
        emit TreasuryFund.StrategyDelisted(address(farm));
        vm.expectEmit(true, false, false, true, address(farm));
        emit IMockFarm.EmergencyWithdrawn(address(cruise), CRUISE_PRINCIPAL, 0);
        vm.expectEmit(false, false, false, true, address(farm));
        emit Pausable.Paused(address(cruise));
        vm.expectEmit(true, true, false, true, address(cruise));
        emit TreasuryFund.EmergencyWithdrawn(address(cruise), address(farm), CRUISE_PRINCIPAL, "risk");

        vm.prank(owner);
        cruise.emergencyWithdraw("risk");

        assertEq(cruise.idle(), CRUISE_PRINCIPAL);
        assertEq(cruise.principal(), 0);
        assertEq(cruise.value(), valueBefore);
        assertEq(cruise.value(), CRUISE_PRINCIPAL);
        assertEq(address(cruise.activeFarm()), address(0));
        assertEq(cruise.strategyCount(), 0);
        assertFalse(cruise.isStrategy(address(farm)));
        assertTrue(farm.paused());
        assertEq(farm.principalOf(address(cruise)), 0);
        assertEq(farm.rewardReserve(), RESERVE);
        assertEq(usdc.balanceOf(address(cruise)), CRUISE_PRINCIPAL);
        assertEq(usdc.balanceOf(address(farm)), RESERVE);
        assertEq(usdc.balanceOf(owner), ownerBefore);
        assertEq(cruise.heldRewards(), 0);
        assertEq(cruise.pendingBuyback(), 0);
        (address strategy, uint256 amount, string memory reason) = cruise.lastEmergencyExit();
        assertEq(strategy, address(farm));
        assertEq(amount, CRUISE_PRINCIPAL);
        assertEq(reason, "risk");
    }

    function test_ExitOfEmptyActiveFarmStillDelists() public {
        MockFarm farm = _farm(500);
        CruiseControl cruise = _cruise(farm);
        vm.prank(owner);
        cruise.setStrategy(farm);
        uint256 idleBefore = cruise.idle();

        vm.recordLogs();
        vm.prank(owner);
        cruise.emergencyWithdraw(" ");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertFalse(_hasTopic(logs, keccak256("EmergencyWithdrawn(address,uint256,uint256)")));
        assertEq(cruise.idle(), idleBefore);
        assertEq(cruise.principal(), 0);
        assertEq(address(cruise.activeFarm()), address(0));
        assertEq(cruise.strategyCount(), 0);
        assertFalse(cruise.isStrategy(address(farm)));
        assertTrue(farm.paused());
        (address strategy, uint256 amount, string memory reason) = cruise.lastEmergencyExit();
        assertEq(strategy, address(farm));
        assertEq(amount, 0);
        assertEq(reason, " ");
    }

    function test_RevertWhen_ExitIsCalledTwice() public {
        (CruiseControl cruise, MockFarm farm) = _cruiseReady(500);
        vm.prank(owner);
        cruise.emergencyWithdraw("once");
        uint256 idleBefore = cruise.idle();

        vm.expectRevert(TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        vm.prank(owner);
        cruise.emergencyWithdraw("twice");

        assertEq(cruise.idle(), idleBefore);
        assertTrue(farm.paused());
        assertFalse(cruise.isStrategy(address(farm)));
        (address strategy,,) = cruise.lastEmergencyExit();
        assertEq(strategy, address(farm));
    }

    function test_RevertWhen_NoActiveFarm() public {
        MockFarm farm = _farm(16_000);
        CruiseControl cruise = _cruise(farm);
        DegenDriver degen = _degen(cruise, _one(farm));

        vm.expectRevert(TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        vm.prank(owner);
        degen.emergencyWithdraw("none");

        assertEq(degen.idle(), 0);
        assertEq(address(degen.activeFarm()), address(0));
        assertTrue(degen.isStrategy(address(farm)));
        assertFalse(farm.paused());
        (address strategy,,) = degen.lastEmergencyExit();
        assertEq(strategy, address(0));
    }

    function test_RevertWhen_ReasonIsEmpty() public {
        (CruiseControl cruise, MockFarm farm) = _cruiseReady(500);
        DegenDriver degen = _degen(cruise, _one(farm));

        vm.expectRevert(TreasuryFund.TreasuryFund__EmptyReason.selector);
        vm.prank(owner);
        cruise.emergencyWithdraw("");

        vm.expectRevert(TreasuryFund.TreasuryFund__EmptyReason.selector);
        vm.prank(owner);
        degen.emergencyWithdraw("");

        assertEq(address(cruise.activeFarm()), address(farm));
        assertFalse(farm.paused());
        assertEq(cruise.idle(), 0);
        assertEq(cruise.principal(), CRUISE_PRINCIPAL);
        (address strategy,,) = cruise.lastEmergencyExit();
        assertEq(strategy, address(0));
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        (CruiseControl cruise,) = _cruiseReady(500);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        cruise.emergencyWithdraw("leak");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(cruise)));
        vm.prank(address(cruise));
        cruise.emergencyWithdraw("leak");
    }

    function test_DirectTransferStaysOutOfIdle() public {
        (CruiseControl cruise, MockFarm farm) = _cruiseReady(500);
        vm.prank(owner);
        usdc.transfer(address(cruise), 123);
        vm.prank(owner);
        usdc.transfer(address(farm), 456);
        uint256 ownerBefore = usdc.balanceOf(owner);

        vm.prank(owner);
        cruise.emergencyWithdraw("direct");

        assertEq(cruise.idle(), CRUISE_PRINCIPAL);
        assertEq(cruise.value(), CRUISE_PRINCIPAL);
        assertEq(usdc.balanceOf(address(cruise)), CRUISE_PRINCIPAL + 123);
        assertEq(usdc.balanceOf(address(farm)), RESERVE + 456);
        assertEq(usdc.balanceOf(owner), ownerBefore);
    }

    function test_ExitWorksWhenRewardLogicReverts() public {
        HaltingDriverClock halting = new HaltingDriverClock();
        uint256 start = 1_000_000;
        halting.setTime(start);
        MockFarm timed = new MockFarm(usdc, halting, 500, owner);
        RoundSchedule timedSchedule = new RoundSchedule(halting, 30 days);
        CruiseControl timedFund =
            new CruiseControl(usdc, halting, timedSchedule, splitter, pool, SHARE_1, SHARE_2, _one(timed), owner);

        vm.startPrank(owner);
        timed.addDepositor(address(timedFund));
        usdc.approve(address(timed), RESERVE);
        timed.fundRewards(RESERVE);
        usdc.approve(address(timedFund), CRUISE_PRINCIPAL + 1);
        timedFund.supply(CRUISE_PRINCIPAL + 1);
        timedFund.setStrategy(timed);
        timedFund.deposit(CRUISE_PRINCIPAL);
        vm.stopPrank();

        halting.setTime(start + 30 days);
        vm.prank(owner);
        timedFund.deposit(1);
        assertEq(timed.accrued(address(timedFund)), CRUISE_30_DAYS);
        uint256 reserveBefore = timed.rewardReserve();
        halting.halt();

        vm.expectRevert(HaltingDriverClock.HaltingDriverClock__Halted.selector);
        timed.accrued(address(timedFund));
        vm.expectRevert(HaltingDriverClock.HaltingDriverClock__Halted.selector);
        vm.prank(address(timedFund));
        timed.claim();

        vm.expectEmit(true, false, false, true, address(timed));
        emit IMockFarm.EmergencyWithdrawn(address(timedFund), CRUISE_PRINCIPAL + 1, CRUISE_30_DAYS);
        vm.prank(owner);
        timedFund.emergencyWithdraw("clock halted");

        assertEq(timedFund.idle(), CRUISE_PRINCIPAL + 1);
        assertEq(timedFund.principal(), 0);
        assertEq(timedFund.value(), CRUISE_PRINCIPAL + 1);
        assertEq(timed.principalOf(address(timedFund)), 0);
        assertEq(timed.rewardReserve(), reserveBefore);
        assertEq(timedFund.heldRewards(), 0);
        assertEq(timedFund.pendingBuyback(), 0);
        assertTrue(timed.paused());
        assertFalse(timedFund.isStrategy(address(timed)));
    }

    function test_PausedFarmRejectsDepositAndClaim() public {
        (CruiseControl cruise, MockFarm farm) = _cruiseReady(500);
        vm.prank(owner);
        cruise.emergencyWithdraw("pause");

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(address(cruise));
        farm.deposit(1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(address(cruise));
        farm.withdraw(1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(address(cruise));
        farm.claim();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        farm.fundRewards(1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        farm.addDepositor(stranger);

        vm.expectRevert(IMockFarm.MockFarm__ZeroAmount.selector);
        vm.prank(address(cruise));
        farm.emergencyWithdraw();
    }

    function test_ExitWorksWhenTheFarmIsAlreadyPaused() public {
        (CruiseControl cruise, MockFarm farm) = _cruiseReady(500);
        vm.prank(address(cruise));
        farm.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(address(cruise));
        farm.deposit(1);

        vm.recordLogs();
        vm.prank(owner);
        cruise.emergencyWithdraw("already");

        assertFalse(_hasTopic(vm.getRecordedLogs(), keccak256("Paused(address)")));
        assertEq(cruise.idle(), CRUISE_PRINCIPAL);
        assertEq(cruise.principal(), 0);
        assertEq(cruise.value(), CRUISE_PRINCIPAL);
        assertTrue(farm.paused());
        assertFalse(cruise.isStrategy(address(farm)));
        assertEq(address(cruise.activeFarm()), address(0));
    }

    function test_RevertWhen_FarmReturnDiffers() public {
        ScriptedFarm farm = new ScriptedFarm(usdc, clock);
        farm.setReturn(5, 4);
        CruiseControl cruise = _cruise(farm);
        vm.prank(owner);
        cruise.setStrategy(farm);

        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__PrincipalMismatch.selector, 5, 4));
        vm.prank(owner);
        cruise.emergencyWithdraw("lie");

        assertEq(address(cruise.activeFarm()), address(farm));
        assertEq(cruise.idle(), 0);
        assertEq(cruise.strategyCount(), 1);
        assertTrue(cruise.isStrategy(address(farm)));
        assertFalse(farm.paused());
        (address strategy,,) = cruise.lastEmergencyExit();
        assertEq(strategy, address(0));
    }

    function test_RevertWhen_ExitReenters() public {
        ScriptedFarm farm = new ScriptedFarm(usdc, clock);
        CruiseControl cruise = _cruise(farm);
        farm.setReturn(1, 1);
        farm.setReenter(cruise);
        vm.prank(owner);
        cruise.setStrategy(farm);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(owner);
        cruise.emergencyWithdraw("again");

        assertEq(address(cruise.activeFarm()), address(farm));
        assertFalse(farm.paused());
        assertTrue(cruise.isStrategy(address(farm)));
        assertEq(cruise.idle(), 0);
    }

    function test_ExitAfterASwitchLeavesTheOldFarmListed() public {
        MockFarm highway = _farm(4_000);
        MockFarm autobahn = _farm(8_000);
        MockFarm drift = _farm(16_000);
        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = highway;
        farms[1] = autobahn;
        farms[2] = drift;
        MockFarm cruiseFarm = _farm(500);
        CruiseControl cruise = _cruise(cruiseFarm);
        DegenDriver degen =
            new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, SHARE_1, SHARE_2, farms, owner);
        vm.startPrank(owner);
        highway.addDepositor(address(degen));
        autobahn.addDepositor(address(degen));
        drift.addDepositor(address(degen));
        usdc.approve(address(cruise), SHARE_1);
        cruise.supply(SHARE_1);
        cruise.setStrategy(cruiseFarm);
        cruise.deposit(SHARE_1);
        usdc.approve(address(degen), SHARE_2);
        degen.supply(SHARE_2);
        cruise.setFund2(degen);
        vm.stopPrank();

        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, highway);
        ballot.setWinner(1, autobahn);
        vm.prank(owner);
        degen.setBallot(ballot);
        vm.prank(owner);
        clock.advanceTime(30 days);
        vm.prank(owner);
        degen.harvest(0);
        vm.prank(owner);
        clock.advanceTime(30 days);
        vm.prank(owner);
        degen.harvest(0);

        assertEq(address(degen.activeFarm()), address(autobahn));
        assertEq(degen.heldRewards(), 0);
        uint256 principalBefore = degen.principal();
        uint256 valueBefore = degen.value();
        assertGt(principalBefore, 0);

        vm.prank(owner);
        degen.emergencyWithdraw("switch");

        assertEq(degen.idle(), principalBefore);
        assertEq(degen.principal(), 0);
        assertEq(degen.value(), valueBefore);
        assertEq(degen.heldRewards(), 0);
        assertEq(degen.pendingBuyback(), 0);
        assertEq(address(degen.activeFarm()), address(0));
        assertEq(degen.strategyCount(), 2);
        assertEq(address(degen.strategyAt(0)), address(highway));
        assertEq(address(degen.strategyAt(1)), address(drift));
        assertTrue(degen.isStrategy(address(highway)));
        assertFalse(degen.isStrategy(address(autobahn)));
        assertTrue(degen.isStrategy(address(drift)));
        assertFalse(highway.paused());
        assertTrue(autobahn.paused());
        assertFalse(drift.paused());
        assertEq(highway.principalOf(address(degen)), 0);
        assertEq(autobahn.principalOf(address(degen)), 0);

        vm.expectRevert(TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        vm.prank(owner);
        degen.emergencyWithdraw("twice");
    }

    function test_ExitLeavesHeldRewardsForTheNextHarvest() public {
        MockFarm first = _farm(500);
        MockFarm second = _farm(500);
        IMockFarm[] memory farms = new IMockFarm[](2);
        farms[0] = first;
        farms[1] = second;
        CruiseControl cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, farms, owner);
        vm.startPrank(owner);
        first.addDepositor(address(cruise));
        second.addDepositor(address(cruise));
        usdc.approve(address(cruise), CRUISE_PRINCIPAL);
        cruise.supply(CRUISE_PRINCIPAL);
        cruise.setStrategy(first);
        cruise.deposit(CRUISE_PRINCIPAL);
        clock.advanceTime(30 days);
        cruise.setStrategy(second);
        vm.stopPrank();

        assertEq(cruise.heldRewards(), CRUISE_30_DAYS);
        assertEq(cruise.principal(), CRUISE_PRINCIPAL);
        assertEq(first.rewardReserve(), RESERVE - CRUISE_30_DAYS);

        vm.prank(owner);
        cruise.emergencyWithdraw("held");

        assertEq(cruise.heldRewards(), CRUISE_30_DAYS);
        assertEq(cruise.pendingBuyback(), 0);
        assertEq(cruise.idle(), CRUISE_PRINCIPAL);
        assertEq(cruise.value(), CRUISE_PRINCIPAL);
        assertEq(usdc.balanceOf(address(cruise)), CRUISE_PRINCIPAL + CRUISE_30_DAYS);
        assertTrue(cruise.isStrategy(address(first)));
        assertFalse(cruise.isStrategy(address(second)));
        assertFalse(first.paused());
        assertTrue(second.paused());
        assertEq(first.rewardReserve(), RESERVE - CRUISE_30_DAYS);

        (uint256 quoted,) = pool.quoteExactInput(IOfficialPool.Direction.Buy, BUYBACK);
        vm.prank(owner);
        cruise.harvest(0);

        ITreasuryFund.Harvest memory harvest_ = cruise.lastHarvest();
        assertEq(harvest_.rewards, CRUISE_30_DAYS);
        assertEq(harvest_.compounded, COMPOUND);
        assertEq(harvest_.buybackSpent, BUYBACK);
        assertEq(harvest_.dvrBurned, quoted);
        assertEq(cruise.idle(), CRUISE_PRINCIPAL + COMPOUND);
        assertEq(cruise.principal(), 0);
        assertEq(cruise.heldRewards(), 0);
        assertEq(cruise.pendingBuyback(), 0);
        assertEq(address(cruise.activeFarm()), address(0));
    }

    function test_Fund1HoldsIdleWhenCruiseIsDelisted() public {
        (CruiseControl cruise, MockFarm farm) = _cruiseReady(500);
        vm.prank(owner);
        cruise.emergencyWithdraw("cruise");

        assertEq(cruise.strategyCount(), 0);
        vm.expectRevert(stdError.indexOOBError);
        cruise.strategyAt(0);

        vm.expectRevert(TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        vm.prank(owner);
        cruise.deposit(1);
        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__StrategyNotAllowed.selector, address(farm)));
        vm.prank(owner);
        cruise.setStrategy(farm);

        vm.prank(owner);
        clock.advanceTime(30 days);
        vm.prank(owner);
        cruise.harvest(0);

        assertEq(cruise.idle(), CRUISE_PRINCIPAL);
        assertEq(cruise.principal(), 0);
        assertEq(cruise.lastHarvest().rewards, 0);
        assertEq(cruise.lastHarvest().compounded, 0);
        assertEq(cruise.lastHarvest().buybackSpent, 0);
        assertEq(address(cruise.activeFarm()), address(0));
    }

    function test_TopUpAfterExitPaysFund2Idle() public {
        MockFarm cruiseFarm = _farm(500);
        MockFarm drift = _farm(16_000);
        CruiseControl cruise = _cruise(cruiseFarm);
        DegenDriver degen = _degen(cruise, _one(drift));
        vm.startPrank(owner);
        drift.addDepositor(address(degen));
        usdc.approve(address(cruise), SHARE_1);
        cruise.supply(SHARE_1);
        cruise.setStrategy(cruiseFarm);
        cruise.deposit(SHARE_1);
        cruise.setFund2(degen);
        cruise.emergencyWithdraw("exit");
        (uint256 fund1Value, uint256 fund2Value, uint256 cap) = cruise.topUpCap();
        assertEq(fund1Value, SHARE_1);
        assertEq(fund2Value, 0);
        assertEq(cap, TOP_UP);

        vm.expectEmit(true, false, false, true, address(degen));
        emit TreasuryFund.CapitalSupplied(address(cruise), TOP_UP, TOP_UP);
        vm.expectEmit(false, false, false, true, address(cruise));
        emit CruiseControl.Fund2ToppedUp(TOP_UP, SHARE_1, 0, "revive");
        cruise.topUpFund2(TOP_UP, "revive");
        vm.stopPrank();

        assertEq(cruise.idle(), FUND_1_AFTER_TOP_UP);
        assertEq(cruise.principal(), 0);
        assertEq(degen.idle(), TOP_UP);
        assertEq(degen.principal(), 0);
        assertEq(address(degen.activeFarm()), address(0));
        assertEq(usdc.balanceOf(address(degen)), TOP_UP);
    }

    function test_RebalanceAfterExitCreditsIdle() public {
        MockFarm cruiseFarm = _farm(500);
        MockFarm drift = _farm(16_000);
        CruiseControl cruise = _cruise(cruiseFarm);
        DegenDriver degen = _degen(cruise, _one(drift));
        vm.startPrank(owner);
        drift.addDepositor(address(degen));
        usdc.approve(address(cruise), SHARE_1);
        cruise.supply(SHARE_1);
        cruise.setStrategy(cruiseFarm);
        cruise.deposit(SHARE_1);
        usdc.approve(address(degen), SHARE_2);
        degen.supply(SHARE_2);
        cruise.setFund2(degen);
        vm.stopPrank();

        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, drift);
        vm.prank(owner);
        degen.setBallot(ballot);
        vm.prank(owner);
        clock.advanceTime(30 days);
        vm.prank(owner);
        degen.harvest(0);
        vm.prank(owner);
        cruise.emergencyWithdraw("before");

        assertEq(cruise.idle(), SHARE_1);
        assertEq(cruise.value(), SHARE_1);
        assertTrue(cruiseFarm.paused());
        assertFalse(drift.paused());

        vm.prank(owner);
        clock.advanceTime(30 days);
        uint256 sumBefore = cruise.value() + degen.value();
        vm.expectEmit(true, false, false, true, address(cruise));
        emit TreasuryFund.CapitalSupplied(address(degen), DRIFT_MOVED, DRIFT_FUND1);
        vm.prank(owner);
        degen.harvest(0);

        assertEq(sumBefore + DRIFT_COMPOUND, DRIFT_SUM);
        assertEq(cruise.value() + degen.value(), DRIFT_SUM);
        assertEq(cruise.idle(), DRIFT_FUND1);
        assertEq(cruise.principal(), 0);
        assertEq(cruiseFarm.principalOf(address(cruise)), 0);
        assertEq(degen.value(), DRIFT_FUND2);
        assertEq(degen.lastHarvest().rewards, DRIFT_REWARDS);
        assertEq(degen.lastHarvest().compounded, DRIFT_COMPOUND);
        assertEq(degen.lastHarvest().buybackSpent, DRIFT_BUYBACK);
        (,, uint256 fund1Value, uint256 fund2Value, uint256 amount) = _rebalance(degen);
        assertEq(fund1Value, SHARE_1);
        assertEq(fund2Value, DRIFT_BEFORE);
        assertEq(amount, DRIFT_MOVED);
    }

    function test_ExitLeavesPendingBuybackUntouched() public {
        MockFarm hot = _farm(10_000);
        RoundSchedule short = new RoundSchedule(clock, 1 days);
        CruiseControl dust = new CruiseControl(usdc, clock, short, splitter, pool, SHARE_1, SHARE_2, _one(hot), owner);
        vm.startPrank(owner);
        hot.addDepositor(address(dust));
        usdc.approve(address(hot), RESERVE);
        hot.fundRewards(RESERVE);
        usdc.approve(address(dust), 730);
        dust.supply(730);
        dust.setStrategy(hot);
        dust.deposit(730);
        clock.advanceTime(1 days);
        dust.harvest(0);
        assertEq(dust.pendingBuyback(), 1);
        assertEq(dust.principal(), 731);
        uint256 valueBefore = dust.value();
        dust.emergencyWithdraw("pending");
        vm.stopPrank();

        assertEq(dust.pendingBuyback(), 1);
        assertEq(dust.idle(), 731);
        assertEq(dust.principal(), 0);
        assertEq(dust.value(), valueBefore);
        assertEq(dust.heldRewards(), 0);
    }

    function _cruiseReady(uint256 apr) private returns (CruiseControl cruise, MockFarm farm) {
        farm = _farm(apr);
        cruise = _cruise(farm);
        vm.startPrank(owner);
        usdc.approve(address(cruise), CRUISE_PRINCIPAL);
        cruise.supply(CRUISE_PRINCIPAL);
        cruise.setStrategy(farm);
        cruise.deposit(CRUISE_PRINCIPAL);
        vm.stopPrank();
    }

    function _farm(uint256 apr) private returns (MockFarm farm) {
        farm = new MockFarm(usdc, clock, apr, owner);
        vm.startPrank(owner);
        usdc.approve(address(farm), RESERVE);
        farm.fundRewards(RESERVE);
        vm.stopPrank();
    }

    function _cruise(IMockFarm farm) private returns (CruiseControl cruise) {
        cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, _one(farm), owner);
        vm.prank(owner);
        MockFarm(address(farm)).addDepositor(address(cruise));
    }

    function _degen(CruiseControl cruise, IMockFarm[] memory farms) private returns (DegenDriver degen) {
        degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, SHARE_1, SHARE_2, farms, owner);
    }

    function _one(IMockFarm farm) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm;
    }

    function _rebalance(DegenDriver degen)
        private
        view
        returns (bool executed, uint256 roundId, uint256 fund1Value, uint256 fund2Value, uint256 amount)
    {
        (executed, roundId, fund1Value, fund2Value, amount) = degen.lastRebalance();
    }

    function _hasTopic(Vm.Log[] memory logs, bytes32 topic) private pure returns (bool found) {
        uint256 count = logs.length;
        for (uint256 i = 0; i < count; i++) {
            if (logs[i].topics[0] == topic) {
                return true;
            }
        }
        return false;
    }
}

/// @title Scripted farm
/// @notice Test farm with a fixed principal, a fixed emergency return, and an optional reentering exit.
contract ScriptedFarm is IMockFarm {
    MockUSDC private immutable i_usdcToken;
    IDriverClock private immutable i_clockTime;
    uint256 private s_principal = 5;
    uint256 private s_returned = 4;
    bool private s_reenter;
    TreasuryFund private s_fund;
    bool private s_paused;

    /// @notice Stores the token and the clock the fund constructor reads.
    /// @param usdc Mock USDC reported by this farm.
    /// @param clock Clock reported by this farm.
    constructor(MockUSDC usdc, IDriverClock clock) {
        i_usdcToken = usdc;
        i_clockTime = clock;
    }

    /// @notice Sets the principal view and the amount {emergencyWithdraw} returns.
    /// @param principal Amount {principalOf} returns, in base units.
    /// @param returned Amount {emergencyWithdraw} returns, in base units.
    function setReturn(uint256 principal, uint256 returned) external {
        s_principal = principal;
        s_returned = returned;
    }

    /// @notice Makes {emergencyWithdraw} call {TreasuryFund.emergencyWithdraw} on `fund`.
    /// @param fund Fund to call.
    function setReenter(TreasuryFund fund) external {
        s_reenter = true;
        s_fund = fund;
    }

    /// @notice Accepts a depositor. The real farm restricts this to its owner.
    function addDepositor(address) external {}

    /// @notice Does nothing.
    function deposit(uint256) external {}

    /// @notice Does nothing.
    function withdraw(uint256) external {}

    /// @notice Returns the scripted amount, after an optional reentering exit.
    /// @return principal Scripted amount, in base units.
    function emergencyWithdraw() external returns (uint256 principal) {
        if (s_reenter) {
            s_fund.emergencyWithdraw("nested");
        }
        principal = s_returned;
    }

    /// @notice Returns zero.
    /// @return paid Zero.
    function claim() external pure returns (uint256 paid) {
        paid = 0;
    }

    /// @notice Records that the farm was paused.
    function pause() external {
        s_paused = true;
    }

    /// @notice Returns zero.
    /// @return accrued_ Zero.
    function accrued(address) external pure returns (uint256 accrued_) {
        accrued_ = 0;
    }

    /// @notice Returns the scripted principal.
    /// @return principal_ Scripted principal, in base units.
    function principalOf(address) external view returns (uint256 principal_) {
        principal_ = s_principal;
    }

    /// @notice Returns zero.
    /// @return totalPrincipal_ Zero.
    function totalPrincipal() external pure returns (uint256 totalPrincipal_) {
        totalPrincipal_ = 0;
    }

    /// @notice Returns zero.
    /// @return rewardReserve_ Zero.
    function rewardReserve() external pure returns (uint256 rewardReserve_) {
        rewardReserve_ = 0;
    }

    /// @notice Returns one basis point.
    /// @return aprBps_ One.
    function aprBps() external pure returns (uint256 aprBps_) {
        aprBps_ = 1;
    }

    /// @notice Returns false.
    /// @return isDepositor_ False.
    function isDepositor(address) external pure returns (bool isDepositor_) {
        isDepositor_ = false;
    }

    /// @notice Returns whether {pause} was called.
    /// @return paused_ True after {pause}.
    function paused() external view returns (bool paused_) {
        paused_ = s_paused;
    }

    /// @notice Returns the token stored in the constructor.
    /// @return usdc_ Mock USDC.
    function i_usdc() external view returns (MockUSDC usdc_) {
        usdc_ = i_usdcToken;
    }

    /// @notice Returns the clock stored in the constructor.
    /// @return clock_ Clock.
    function i_clock() external view returns (IDriverClock clock_) {
        clock_ = i_clockTime;
    }
}
