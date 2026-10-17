// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {IOfficialPool} from "../../src/interfaces/IOfficialPool.sol";
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
import {RebalanceFarm} from "./Rebalance.t.sol";

contract TopUpTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    RoundSchedule internal schedule;
    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC(owner);
        DriverToken token = new DriverToken(owner);
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

    function test_CapRestoresTheRatioAndTheNextHarvestMovesZero() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 180, 20, true);
        uint256 sum = cruise.value() + degen.value();

        (uint256 fund1Value, uint256 fund2Value, uint256 cap) = cruise.topUpCap();
        assertEq(fund1Value, 180);
        assertEq(fund2Value, 20);
        assertEq(cap, 30);

        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, 30, 31));
        vm.prank(owner);
        cruise.topUpFund2(31, "revive");

        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Approval(address(cruise), address(degen), 30);
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Transfer(address(cruise), address(degen), 30);
        vm.expectEmit(true, false, false, true, address(degen));
        emit TreasuryFund.CapitalSupplied(address(cruise), 30, 50);
        vm.expectEmit(true, true, false, true, address(usdc));
        emit IERC20.Approval(address(cruise), address(degen), 0);
        vm.expectEmit(false, false, false, true, address(cruise));
        emit CruiseControl.Fund2ToppedUp(30, 180, 20, "revive");
        vm.prank(owner);
        cruise.topUpFund2(30, "revive");

        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
        assertEq(cruise.value() + degen.value(), sum);
        _assertAllowances(cruise, degen);

        _skip(30 days);
        vm.prank(owner);
        degen.harvest(0);
        (,,,, uint256 amount) = degen.lastRebalance();
        assertEq(amount, 0);
        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
    }

    function test_RoundingCapMovesOne() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(SHARE_1, SHARE_2);
        _seed(cruise, degen, SHARE_1 + 4, SHARE_2, true);

        (,, uint256 cap) = cruise.topUpCap();
        assertEq(cap, 1);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, 1, 2));
        vm.prank(owner);
        cruise.topUpFund2(2, "dust");

        vm.prank(owner);
        cruise.topUpFund2(1, "dust");
        assertEq(cruise.value(), SHARE_1 + 3);
        assertEq(degen.value(), SHARE_2 + 1);

        _skip(30 days);
        vm.prank(owner);
        degen.harvest(0);
        (,,,, uint256 amount) = degen.lastRebalance();
        assertEq(amount, 0);
        assertEq(cruise.value(), SHARE_1 + 3);
        assertEq(degen.value(), SHARE_2 + 1);
    }

    function test_TwoTopUpsAddUntilTheCap() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 180, 20, true);

        vm.startPrank(owner);
        cruise.topUpFund2(10, "first");
        assertEq(cruise.value(), 170);
        assertEq(degen.value(), 30);
        (,, uint256 cap) = cruise.topUpCap();
        assertEq(cap, 20);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, 20, 21));
        cruise.topUpFund2(21, "second");
        cruise.topUpFund2(20, "second");
        vm.stopPrank();

        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
        (,, cap) = cruise.topUpCap();
        assertEq(cap, 0);
    }

    function test_ZeroAmountRevertsBeforeTheCap() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 150, 50, true);
        vm.prank(owner);
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
        cruise.topUpFund2(0, "keep");
        assertEq(cruise.value(), 150);

        (CruiseControl above, DegenDriver other,) = _open(3, 1);
        _seed(above, other, 180, 20, true);
        vm.prank(owner);
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
        above.topUpFund2(0, "keep");
        assertEq(above.value(), 180);
    }

    function test_EmptyReasonRevertsAndWhitespaceIsAllowed() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 180, 20, true);

        vm.prank(owner);
        vm.expectRevert(CruiseControl.CruiseControl__EmptyReason.selector);
        cruise.topUpFund2(30, "");
        vm.prank(owner);
        vm.expectRevert(CruiseControl.CruiseControl__EmptyReason.selector);
        cruise.topUpFund2(0, "");
        assertEq(cruise.value(), 180);

        vm.prank(owner);
        cruise.topUpFund2(30, " ");
        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
    }

    function test_BothValuesZeroHaveNoCap() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 0, 0, true);

        (uint256 fund1Value, uint256 fund2Value, uint256 cap) = cruise.topUpCap();
        assertEq(fund1Value, 0);
        assertEq(fund2Value, 0);
        assertEq(cap, 0);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, 0, 1));
        cruise.topUpFund2(1, "none");
    }

    function test_IdleThenFarmPaysIdleFirst() public {
        (CruiseControl cruise, DegenDriver degen, MockFarm farm) = _open(3, 1);
        vm.startPrank(owner);
        cruise.setStrategy(farm);
        usdc.approve(address(cruise), 180);
        cruise.supply(180);
        cruise.deposit(170);
        usdc.approve(address(degen), 20);
        degen.supply(20);
        cruise.setFund2(degen);
        cruise.topUpFund2(30, "mixed");
        vm.stopPrank();

        assertEq(cruise.idle(), 0);
        assertEq(cruise.principal(), 150);
        assertEq(farm.principalOf(address(cruise)), 150);
        assertEq(degen.idle(), 50);
        assertEq(degen.principal(), 0);
        assertEq(cruise.value() + degen.value(), 200);
        _assertAllowances(cruise, degen);
    }

    function test_Fund2DepositsThePayment() public {
        (CruiseControl cruise, DegenDriver degen, MockFarm farm) = _open(3, 1);
        _seed(cruise, degen, 180, 20, true);
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, farm);
        vm.prank(owner);
        degen.setBallot(ballot);

        _skip(30 days);
        vm.prank(owner);
        degen.harvest(0);
        assertEq(degen.principal(), 20);
        assertEq(degen.idle(), 0);

        vm.prank(owner);
        cruise.topUpFund2(30, "deploy");
        assertEq(cruise.idle(), 150);
        assertEq(degen.principal(), 50);
        assertEq(degen.idle(), 0);
        assertEq(farm.principalOf(address(degen)), 50);
        _assertAllowances(cruise, degen);
    }

    function test_TopUpDoesNotWaitForARound() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 180, 20, true);
        (bool ready,) = cruise.harvestableRound();
        assertFalse(ready);

        vm.prank(owner);
        cruise.topUpFund2(30, "now");
        assertEq(cruise.value(), 150);
        assertEq(degen.value(), 50);
        (bool harvested,) = cruise.lastHarvestedRound();
        assertFalse(harvested);
    }

    function test_ReleasedTaxRaisesTheCapAndCanMove() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 0, 0, true);
        vm.startPrank(owner);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(cruise));
        usdc.approve(address(pool), 100 * 10 ** 6);
        pool.swapExactInput(IOfficialPool.Direction.Buy, 100 * 10 ** 6, 0, block.timestamp);
        vm.stopPrank();
        assertEq(cruise.value(), 0);

        _skip(30 days);
        vm.prank(owner);
        cruise.harvest(0);
        assertEq(cruise.value(), 400_000);
        (,, uint256 cap) = cruise.topUpCap();
        assertEq(cap, 100_000);

        vm.prank(owner);
        cruise.topUpFund2(100_000, "tax");
        assertEq(cruise.value(), 300_000);
        assertEq(degen.value(), 100_000);
        assertEq(cruise.value() + degen.value(), 400_000);
    }

    function test_DirectDonationDoesNotRaiseTheCap() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 150, 50, true);
        vm.prank(owner);
        usdc.mint(address(cruise), 7);

        (,, uint256 cap) = cruise.topUpCap();
        assertEq(cap, 0);
        assertEq(cruise.value(), 150);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, 0, 1));
        cruise.topUpFund2(1, "gift");
        assertEq(usdc.balanceOf(address(cruise)), 157);
    }

    function test_RevertWhen_Fund2IsNotSet() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 180, 20, false);

        vm.expectRevert(CruiseControl.CruiseControl__Fund2NotSet.selector);
        cruise.topUpCap();
        vm.prank(owner);
        vm.expectRevert(CruiseControl.CruiseControl__Fund2NotSet.selector);
        cruise.topUpFund2(0, "");
        assertEq(cruise.value(), 180);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 180, 20, true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        cruise.topUpFund2(0, "");
    }

    function test_RevertWhen_AcceptTopUpCallerIsNotFund1() public {
        (CruiseControl cruise, DegenDriver degen,) = _open(3, 1);
        _seed(cruise, degen, 180, 20, true);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(DegenDriver.DegenDriver__NotFund1.selector, stranger));
        degen.acceptTopUp(0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DegenDriver.DegenDriver__NotFund1.selector, owner));
        degen.acceptTopUp(1);

        vm.prank(address(degen));
        vm.expectRevert(abi.encodeWithSelector(DegenDriver.DegenDriver__NotFund1.selector, address(degen)));
        degen.acceptTopUp(1);

        vm.prank(address(cruise));
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
        degen.acceptTopUp(0);
    }

    function test_RevertWhen_WithdrawReentersTheTopUp() public {
        RebalanceFarm farm = new RebalanceFarm(usdc, clock);
        CruiseControl cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, 3, 1, _one(farm), owner);
        DegenDriver degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, 3, 1, _one(farm), owner);
        vm.startPrank(owner);
        cruise.setStrategy(farm);
        usdc.approve(address(cruise), 180);
        cruise.supply(180);
        cruise.deposit(180);
        usdc.approve(address(degen), 20);
        degen.supply(20);
        cruise.setFund2(degen);
        vm.stopPrank();
        farm.setHook(RebalanceFarm.Hook.Withdraw, cruise);

        vm.prank(owner);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        cruise.topUpFund2(30, "again");
    }

    function test_RevertWhen_Fund2DepositReentersHarvest() public {
        RebalanceFarm farm = new RebalanceFarm(usdc, clock);
        CruiseControl cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, 3, 1, _one(farm), owner);
        DegenDriver degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, 3, 1, _one(farm), owner);
        _seed(cruise, degen, 180, 20, true);
        MappedBallot ballot = new MappedBallot();
        ballot.setWinner(0, farm);
        vm.prank(owner);
        degen.setBallot(ballot);
        _skip(30 days);
        vm.prank(owner);
        degen.harvest(0);
        farm.setHook(RebalanceFarm.Hook.Deposit, degen);

        vm.prank(owner);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        cruise.topUpFund2(30, "again");
    }

    function _open(uint256 share1, uint256 share2)
        private
        returns (CruiseControl cruise, DegenDriver degen, MockFarm farm)
    {
        farm = new MockFarm(usdc, clock, 1, owner);
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

    function _skip(uint256 seconds_) private {
        vm.prank(owner);
        clock.advanceTime(seconds_);
    }

    function _assertAllowances(CruiseControl cruise, DegenDriver degen) private view {
        assertEq(usdc.allowance(address(cruise), address(degen)), 0);
        assertEq(usdc.allowance(address(degen), address(cruise)), 0);
    }

    function _one(IMockFarm farm_) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm_;
    }
}
