// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

contract RebalanceTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;

    uint256 internal constant DRIFT_REWARDS = 657_534_246;
    uint256 internal constant DRIFT_COMPOUND = 328_767_123;
    uint256 internal constant DRIFT_BUYBACK = 328_767_123;
    uint256 internal constant DRIFT_BEFORE = 5_328_767_123;
    uint256 internal constant DRIFT_MOVED = 246_575_342;
    uint256 internal constant DRIFT_FUND1 = 15_246_575_342;
    uint256 internal constant DRIFT_FUND2 = 5_082_191_781;
    uint256 internal constant DRIFT_SUM = 20_328_767_123;

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

    function test_DriftHarvestMovesTheWorkedAmounts() public {
        (CruiseControl cruise, DegenDriver degen, MockFarm drift) = _open(SHARE_1, SHARE_2, 16_000);
        vm.startPrank(owner);
        usdc.approve(address(drift), 1_000_000 * 10 ** 6);
        drift.fundRewards(1_000_000 * 10 ** 6);
        vm.stopPrank();
        _seed(cruise, degen, SHARE_1, SHARE_2, true);
        _activate(degen, drift);

        _skip(30 days);
        _harvest(degen);

        (bool executed, uint256 roundId, uint256 fund1Value, uint256 fund2Value, uint256 amount) = degen.lastRebalance();
        assertTrue(executed);
        assertEq(roundId, 0);
        assertEq(fund1Value, SHARE_1);
        assertEq(fund2Value, SHARE_2);
        assertEq(amount, 0);
        assertEq(degen.principal(), SHARE_2);
        assertEq(cruise.value(), SHARE_1);
        ITreasuryFund.Harvest memory first = degen.lastHarvest();
        assertEq(first.rewards, 0);
        assertEq(first.compounded, 0);
        assertEq(first.buybackSpent, 0);

        _skip(30 days);
        vm.recordLogs();
        _harvest(degen);

        (roundId, fund1Value, fund2Value, amount) = _findRebalanced(vm.getRecordedLogs());
        assertEq(roundId, 1);
        assertEq(fund1Value, SHARE_1);
        assertEq(fund2Value, DRIFT_BEFORE);
        assertEq(amount, DRIFT_MOVED);

        ITreasuryFund.Harvest memory second = degen.lastHarvest();
        assertEq(second.roundId, 1);
        assertEq(second.rewards, DRIFT_REWARDS);
        assertEq(second.compounded, DRIFT_COMPOUND);
        assertEq(second.buybackSpent, DRIFT_BUYBACK);
        assertEq(second.pendingBuyback, 0);
        assertGt(second.dvrBurned, 0);

        (executed, roundId, fund1Value, fund2Value, amount) = degen.lastRebalance();
        assertTrue(executed);
        assertEq(roundId, 1);
        assertEq(fund1Value, SHARE_1);
        assertEq(fund2Value, DRIFT_BEFORE);
        assertEq(amount, DRIFT_MOVED);
        assertEq(cruise.value(), DRIFT_FUND1);
        assertEq(degen.value(), DRIFT_FUND2);
        assertEq(cruise.value() + degen.value(), DRIFT_SUM);
        assertEq(fund1Value + fund2Value, DRIFT_SUM);
        assertEq(degen.idle(), 0);
        assertEq(degen.principal(), DRIFT_FUND2);
        assertEq(cruise.idle(), DRIFT_FUND1);
        _assertAllowances(cruise, degen);
    }

    function test_BelowShareMovesIdleAndTheNextHarvestMovesZero() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 100, 100, true);
        uint256 sum = cruise.value() + degen.value();

        _skip(30 days);
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Approval(address(degen), address(cruise), 50);
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(degen), address(cruise), 50);
        vm.expectEmit(true, false, false, true, address(cruise));
        emit TreasuryFund.CapitalSupplied(address(degen), 50, 150);
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Approval(address(degen), address(cruise), 0);
        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.Rebalanced(0, 100, 100, 50);
        _harvest(degen);

        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
        assertEq(cruise.idle(), 150);
        assertEq(degen.idle(), 50);
        assertEq(degen.principal(), 0);
        assertEq(cruise.value() + degen.value(), sum);
        _assertAllowances(cruise, degen);

        _skip(30 days);
        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.Rebalanced(1, 150, 50, 0);
        _harvest(degen);

        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
        (,, uint256 fund1Value, uint256 fund2Value, uint256 amount) = degen.lastRebalance();
        assertEq(fund1Value, 150);
        assertEq(fund2Value, 50);
        assertEq(amount, 0);
    }

    function test_AtShareMovesZero() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 150, 50, true);
        _skip(30 days);
        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.Rebalanced(0, 150, 50, 0);
        _harvest(degen);

        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
        assertEq(usdc.balanceOf(address(degen)), 50);
    }

    function test_AboveShareDoesNotReduceFund1() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 180, 20, true);
        _skip(30 days);
        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.Rebalanced(0, 180, 20, 0);
        _harvest(degen);

        assertEq(cruise.value(), 180);
        assertEq(degen.value(), 20);
        assertEq(cruise.idle(), 180);
        assertEq(degen.idle(), 20);
    }

    function test_RoundingMovesOneThenZero() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(SHARE_1, SHARE_2, 500);
        _seed(cruise, degen, SHARE_1, SHARE_2 + 2, true);
        uint256 sum = SHARE_1 + SHARE_2 + 2;

        _skip(30 days);
        _harvest(degen);

        (,, uint256 fund1Value, uint256 fund2Value, uint256 amount) = degen.lastRebalance();
        assertEq(fund1Value, SHARE_1);
        assertEq(fund2Value, SHARE_2 + 2);
        assertEq(amount, 1);
        assertEq(cruise.value(), SHARE_1 + 1);
        assertEq(degen.value(), SHARE_2 + 1);
        assertEq(cruise.value() + degen.value(), sum);

        _skip(30 days);
        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.Rebalanced(1, SHARE_1 + 1, SHARE_2 + 1, 0);
        _harvest(degen);

        assertEq(cruise.value(), SHARE_1 + 1);
        assertEq(degen.value(), SHARE_2 + 1);
        (,,, fund2Value, amount) = degen.lastRebalance();
        assertEq(fund2Value, SHARE_2 + 1);
        assertEq(amount, 0);
    }

    function test_ActiveFarmPaysTheWholeMove() public {
        (CruiseControl cruise, DegenDriver degen, MockFarm farm) = _open(3, 1, 1);
        _seed(cruise, degen, 100, 100, true);
        _activate(degen, farm);

        _skip(30 days);
        _harvest(degen);

        assertEq(degen.idle(), 0);
        assertEq(degen.principal(), 50);
        assertEq(farm.principalOf(address(degen)), 50);
        assertEq(usdc.balanceOf(address(degen)), 0);
        assertEq(cruise.idle(), 150);
        assertEq(cruise.value() + degen.value(), 200);
        _assertAllowances(cruise, degen);
    }

    function test_Fund1DepositsThePayment() public {
        (CruiseControl cruise, DegenDriver degen, MockFarm farm) = _open(3, 1, 1);
        vm.startPrank(owner);
        cruise.setStrategy(farm);
        usdc.approve(address(cruise), 100);
        cruise.supply(100);
        cruise.deposit(100);
        usdc.approve(address(degen), 100);
        degen.supply(100);
        cruise.setFund2(degen);
        vm.stopPrank();

        _skip(30 days);
        _harvest(degen);

        assertEq(cruise.principal(), 150);
        assertEq(cruise.idle(), 0);
        assertEq(farm.principalOf(address(cruise)), 150);
        assertEq(degen.idle(), 50);
        assertEq(degen.principal(), 0);
        _assertAllowances(cruise, degen);
    }

    function test_ShortReserveAccruedRewardsSurviveTheWithdraw() public {
        (CruiseControl cruise, DegenDriver degen, MockFarm farm) = _open(3, 1, 16_000);
        vm.startPrank(owner);
        usdc.approve(address(farm), 100);
        farm.fundRewards(100);
        vm.stopPrank();
        _seed(cruise, degen, 0, 1_000_000_000, true);
        _activate(degen, farm);

        _skip(30 days);
        _harvest(degen);
        assertEq(degen.principal(), 250_000_000);

        _skip(30 days);
        _harvest(degen);

        assertEq(farm.accrued(address(degen)), 32_876_612);
        assertEq(farm.rewardReserve(), 0);
        assertEq(degen.lastHarvest().rewards, 100);
        assertEq(degen.principal(), 250_000_013);
        (,,,, uint256 amount) = degen.lastRebalance();
        assertEq(amount, 37);
    }

    function test_DeferredBuybackStaysWhileCapitalMoves() public {
        TaxSplitter tinySplitter = new TaxSplitter(usdc, owner);
        OfficialPool tiny = new OfficialPool(token, usdc, tinySplitter, owner, 100);
        RoundSchedule short = new RoundSchedule(clock, 1 days);
        vm.startPrank(owner);
        tinySplitter.setPool(address(tiny));
        token.mint(owner, 1);
        usdc.mint(owner, 10_000 * 10 ** 6);
        token.approve(address(tiny), 1);
        usdc.approve(address(tiny), 10_000 * 10 ** 6);
        tiny.addLiquidity(1, 10_000 * 10 ** 6);
        vm.stopPrank();

        MockFarm hot = new MockFarm(usdc, clock, 10_000, owner);
        CruiseControl cruise = new CruiseControl(usdc, clock, short, tinySplitter, tiny, 3, 1, _one(hot), owner);
        DegenDriver degen = new DegenDriver(usdc, clock, short, tinySplitter, tiny, cruise, 3, 1, _one(hot), owner);
        vm.startPrank(owner);
        hot.addDepositor(address(degen));
        usdc.approve(address(hot), 1_000_000 * 10 ** 6);
        hot.fundRewards(1_000_000 * 10 ** 6);
        vm.stopPrank();
        _seed(cruise, degen, 0, 73_000, true);
        _activate(degen, hot);

        _skip(1 days);
        _harvest(degen);
        assertEq(degen.principal(), 18_250);

        _skip(1 days);
        _harvest(degen);

        assertEq(degen.lastHarvest().rewards, 50);
        assertEq(degen.lastHarvest().compounded, 25);
        assertEq(degen.pendingBuyback(), 25);
        assertEq(usdc.balanceOf(address(degen)), 25);
        assertEq(degen.principal(), 18_257);
        (,,,, uint256 amount) = degen.lastRebalance();
        assertEq(amount, 18);
        assertEq(degen.dvrBoughtBack(), 0);
    }

    function test_ReleasedTaxIsCountedAndMayMove() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 0, 0, true);
        vm.startPrank(owner);
        splitter.setRecipient(TaxSplitter.FundId.Fund2, address(degen));
        usdc.approve(address(pool), 100 * 10 ** 6);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100 * 10 ** 6, 0, block.timestamp);
        vm.stopPrank();
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 400_000);
        assertEq(degen.value(), 0);

        _skip(30 days);
        _harvest(degen);

        (,, uint256 fund1Value, uint256 fund2Value, uint256 amount) = degen.lastRebalance();
        assertEq(fund1Value, 0);
        assertEq(fund2Value, 400_000);
        assertEq(amount, 300_000);
        assertEq(degen.value(), 100_000);
        assertEq(cruise.value(), 300_000);
        assertEq(degen.value() + cruise.value(), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 0);
    }

    function test_Fund2HarvestFirstIgnoresUnreleasedFund1Tax() public {
        (CruiseControl cruise, DegenDriver degen) = _taxed(100, 100);

        _skip(30 days);
        _harvest(degen);

        (,, uint256 fund1Value, uint256 fund2Value, uint256 amount) = degen.lastRebalance();
        assertEq(fund1Value, 100);
        assertEq(fund2Value, 400_100);
        assertEq(amount, 300_050);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(cruise.value(), 300_150);
        assertEq(degen.value(), 100_050);
    }

    function test_Fund1HarvestFirstUsesThePostHarvestValue() public {
        (CruiseControl cruise, DegenDriver degen) = _taxed(100, 100);

        _skip(30 days);
        vm.prank(owner);
        cruise.harvest(0);
        assertEq(cruise.value(), 400_100);
        _harvest(degen);

        (,, uint256 fund1Value, uint256 fund2Value, uint256 amount) = degen.lastRebalance();
        assertEq(fund1Value, 400_100);
        assertEq(fund2Value, 400_100);
        assertEq(amount, 200_050);
        assertEq(cruise.value(), 600_150);
        assertEq(degen.value(), 200_050);
    }

    function test_DirectDonationDoesNotMove() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 150, 50, true);
        vm.prank(owner);
        usdc.mint(address(degen), 7);

        _skip(30 days);
        _harvest(degen);

        assertEq(degen.value(), 50);
        assertEq(degen.idle(), 50);
        assertEq(usdc.balanceOf(address(degen)), 57);
        (,,,, uint256 amount) = degen.lastRebalance();
        assertEq(amount, 0);
        assertEq(cruise.value(), 150);
    }

    function test_RevertWhen_HarvestWouldMoveBeforeFund2IsSet() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 0, 100, false);
        assertEq(address(cruise.fund2()), address(0));

        _skip(30 days);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__NotFund2.selector, address(degen)));
        _harvest(degen);

        (bool executed,,,,) = degen.lastRebalance();
        assertFalse(executed);
        (bool ready, uint256 roundId) = degen.harvestableRound();
        assertTrue(ready);
        assertEq(roundId, 0);
        assertEq(degen.idle(), 100);
        assertEq(cruise.value(), 0);
    }

    function test_ZeroMoveSucceedsBeforeFund2IsSet() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 180, 20, false);

        _skip(30 days);
        vm.expectEmit(true, false, false, true, address(degen));
        emit DegenDriver.Rebalanced(0, 180, 20, 0);
        _harvest(degen);

        assertEq(address(cruise.fund2()), address(0));
        assertEq(cruise.value(), 180);
        assertEq(degen.value(), 20);
        (bool executed,,,, uint256 amount) = degen.lastRebalance();
        assertTrue(executed);
        assertEq(amount, 0);
    }

    function test_RevertWhen_AcceptRebalanceCallerIsNotFund2() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 100, 100, true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__NotFund2.selector, stranger));
        cruise.acceptRebalance(1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__NotFund2.selector, owner));
        cruise.acceptRebalance(1);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__NotFund2.selector, stranger));
        cruise.acceptRebalance(0);
    }

    function test_RevertWhen_Fund2AcceptsZero() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1, 500);
        _seed(cruise, degen, 100, 100, true);

        vm.prank(address(degen));
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
        cruise.acceptRebalance(0);
    }

    function test_RevertWhen_WithdrawReentersHarvest() public {
        RebalanceFarm farm = new RebalanceFarm(usdc, clock);
        CruiseControl cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, 3, 1, _one(farm), owner);
        DegenDriver degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, 3, 1, _one(farm), owner);
        _seed(cruise, degen, 100, 100, true);
        _activate(degen, farm);
        farm.setHook(RebalanceFarm.Hook.Withdraw, degen);

        _skip(30 days);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _harvest(degen);
    }

    function test_RevertWhen_Fund1DepositReentersHarvest() public {
        RebalanceFarm farm = new RebalanceFarm(usdc, clock);
        CruiseControl cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, 3, 1, _one(farm), owner);
        DegenDriver degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, 3, 1, _one(farm), owner);
        vm.startPrank(owner);
        cruise.setStrategy(farm);
        usdc.approve(address(cruise), 100);
        cruise.supply(100);
        cruise.deposit(100);
        usdc.approve(address(degen), 100);
        degen.supply(100);
        cruise.setFund2(degen);
        vm.stopPrank();
        farm.setHook(RebalanceFarm.Hook.Deposit, cruise);

        _skip(30 days);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _harvest(degen);
    }

    function _open(uint256 share1, uint256 share2, uint256 apr)
        private
        returns (CruiseControl cruise, DegenDriver degen, MockFarm farm)
    {
        farm = new MockFarm(usdc, clock, apr, owner);
        IMockFarm[] memory farms = _one(farm);
        cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, share1, share2, farms, owner);
        degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, share1, share2, farms, owner);
        vm.startPrank(owner);
        farm.addDepositor(address(cruise));
        farm.addDepositor(address(degen));
        vm.stopPrank();
    }

    function _seed(CruiseControl cruise, DegenDriver degen, uint256 fund1Amount, uint256 fund2Amount, bool link)
        private
    {
        vm.startPrank(owner);
        if (fund1Amount != 0) {
            usdc.approve(address(cruise), fund1Amount);
            cruise.supply(fund1Amount);
        }
        if (fund2Amount != 0) {
            usdc.approve(address(degen), fund2Amount);
            degen.supply(fund2Amount);
        }
        if (link) {
            cruise.setFund2(degen);
        }
        vm.stopPrank();
    }

    function _taxed(uint256 fund1Amount, uint256 fund2Amount)
        private
        returns (CruiseControl cruise, DegenDriver degen)
    {
        (cruise, degen,) = _open(3, 1, 500);
        _seed(cruise, degen, fund1Amount, fund2Amount, true);
        vm.startPrank(owner);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(cruise));
        splitter.setRecipient(TaxSplitter.FundId.Fund2, address(degen));
        usdc.approve(address(pool), 100 * 10 ** 6);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100 * 10 ** 6, 0, block.timestamp);
        vm.stopPrank();
    }

    function _activate(DegenDriver degen, IMockFarm farm) private {
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, farm);
        vm.prank(owner);
        degen.setBallot(ballot);
    }

    function _harvest(DegenDriver degen) private {
        vm.prank(owner);
        degen.harvest(0);
    }

    function _skip(uint256 seconds_) private {
        vm.prank(owner);
        clock.advanceTime(seconds_);
    }

    function _assertAllowances(CruiseControl cruise, DegenDriver degen) private view {
        assertEq(usdc.allowance(address(degen), address(cruise)), 0);
        assertEq(usdc.allowance(address(cruise), address(degen)), 0);
    }

    function _findRebalanced(Vm.Log[] memory logs)
        private
        pure
        returns (uint256 roundId, uint256 fund1Value, uint256 fund2Value, uint256 amount)
    {
        bytes32 topic = keccak256("Rebalanced(uint256,uint256,uint256,uint256)");
        bool found;
        uint256 count = logs.length;
        for (uint256 i = 0; i < count; i++) {
            if (logs[i].topics[0] != topic) {
                continue;
            }
            found = true;
            roundId = uint256(logs[i].topics[1]);
            (fund1Value, fund2Value, amount) = abi.decode(logs[i].data, (uint256, uint256, uint256));
        }
        assertTrue(found);
    }

    function _one(IMockFarm farm_) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm_;
    }
}

/// @title Rebalance farm
/// @notice Test farm that tracks principal and can call harvest from deposit or withdraw.
contract RebalanceFarm is IMockFarm {
    using SafeERC20 for IERC20;

    /// @notice Which call reenters harvest.
    enum Hook {
        None,
        Withdraw,
        Deposit
    }

    /// @notice Mock USDC this farm reports.
    MockUSDC public immutable i_usdc;

    /// @notice Clock this farm reports.
    IDriverClock public immutable i_clock;

    Hook private s_hook;
    TreasuryFund private s_target;
    mapping(address account => uint256 amount) private s_principal;

    /// @notice Stores the token and the clock the fund constructor reads.
    /// @param usdc Mock USDC reported by this farm.
    /// @param clock Clock reported by this farm.
    constructor(MockUSDC usdc, IDriverClock clock) {
        i_usdc = usdc;
        i_clock = clock;
    }

    /// @notice Chooses the call that reenters `target`.
    /// @param hook Call that reenters. {Hook.None} does not.
    /// @param target Fund that call harvests.
    function setHook(Hook hook, TreasuryFund target) external {
        s_hook = hook;
        s_target = target;
    }

    /// @notice Pulls principal, after an optional harvest call.
    /// @param amount mUSDC to pull, in base units.
    function deposit(uint256 amount) external {
        if (s_hook == Hook.Deposit) {
            s_target.harvest(0);
        }
        s_principal[msg.sender] += amount;
        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Returns principal, after an optional harvest call.
    /// @param amount mUSDC to return, in base units.
    function withdraw(uint256 amount) external {
        if (s_hook == Hook.Withdraw) {
            s_target.harvest(0);
        }
        s_principal[msg.sender] -= amount;
        IERC20(i_usdc).safeTransfer(msg.sender, amount);
    }

    /// @notice Returns zero.
    /// @return principal Zero.
    function emergencyWithdraw() external pure returns (uint256 principal) {
        principal = 0;
    }

    /// @notice Returns zero.
    /// @return paid Zero.
    function claim() external pure returns (uint256 paid) {
        paid = 0;
    }

    /// @notice Returns zero.
    /// @return accrued_ Zero.
    function accrued(address) external pure returns (uint256 accrued_) {
        accrued_ = 0;
    }

    /// @notice Returns the principal this farm recorded for `account`.
    /// @param account Account to query.
    /// @return principal_ Recorded principal, in base units.
    function principalOf(address account) external view returns (uint256 principal_) {
        principal_ = s_principal[account];
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
}
