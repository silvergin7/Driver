// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverClock} from "../../src/DriverClock.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {HaltingDriverClock} from "../mocks/HaltingDriverClock.sol";
import {SettableDriverClock} from "../mocks/SettableDriverClock.sol";

contract MockFarmTest is Test {
    uint256 internal constant APR = 500;
    uint256 internal constant CRUISE_PRINCIPAL = 15_000 * 10 ** 6;
    uint256 internal constant CRUISE_30_DAYS = 61_643_835;
    uint256 internal constant ONE_USDC = 1 * 10 ** 6;

    MockUSDC internal usdc;
    DemoDriverClock internal demo;
    MockFarm internal farm;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        usdc = new MockUSDC(owner);
        demo = new DemoDriverClock(owner);
        farm = new MockFarm(usdc, demo, APR, owner);
        vm.prank(owner);
        usdc.mint(owner, 1_000_000 * 10 ** 6);
    }

    function test_ConstructorStoresConfig() public view {
        assertEq(address(farm.i_usdc()), address(usdc));
        assertEq(address(farm.i_clock()), address(demo));
        assertEq(farm.i_aprBps(), APR);
        assertEq(farm.aprBps(), APR);
        assertEq(farm.owner(), owner);
        assertEq(farm.BPS_DENOMINATOR(), 10_000);
        assertEq(farm.SECONDS_PER_YEAR(), 365 days);
        assertEq(farm.totalPrincipal(), 0);
        assertEq(farm.rewardReserve(), 0);
        assertFalse(farm.isDepositor(alice));
    }

    function test_RevertWhen_UsdcIsZeroAddress() public {
        vm.expectRevert(MockFarm.MockFarm__ZeroAddress.selector);
        new MockFarm(MockUSDC(address(0)), demo, APR, owner);
    }

    function test_RevertWhen_ClockIsZeroAddress() public {
        vm.expectRevert(MockFarm.MockFarm__ZeroAddress.selector);
        new MockFarm(usdc, IDriverClock(address(0)), APR, owner);
    }

    function test_RevertWhen_AprIsZero() public {
        vm.expectRevert(MockFarm.MockFarm__ZeroApr.selector);
        new MockFarm(usdc, demo, 0, owner);
    }

    function test_RevertWhen_OwnerIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new MockFarm(usdc, demo, APR, address(0));
    }

    function test_AddDepositorEmitsAndAllowsDeposit() public {
        vm.expectEmit(address(farm));
        emit MockFarm.DepositorAdded(alice);

        vm.prank(owner);
        farm.addDepositor(alice);

        assertTrue(farm.isDepositor(alice));
    }

    function test_RevertWhen_AddDepositorIsZeroAddress() public {
        vm.expectRevert(MockFarm.MockFarm__ZeroAddress.selector);
        vm.prank(owner);
        farm.addDepositor(address(0));
    }

    function test_RevertWhen_DepositorIsAddedTwice() public {
        vm.prank(owner);
        farm.addDepositor(alice);

        vm.expectRevert(abi.encodeWithSelector(MockFarm.MockFarm__DepositorAlreadyAdded.selector, alice));
        vm.prank(owner);
        farm.addDepositor(alice);
    }

    function test_RevertWhen_AddDepositorCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        farm.addDepositor(alice);
    }

    function test_RevertWhen_FundRewardsCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        farm.fundRewards(1);
    }

    function test_RevertWhen_DepositCallerIsNotDepositor() public {
        vm.expectRevert(abi.encodeWithSelector(IMockFarm.MockFarm__CallerNotDepositor.selector, alice));
        vm.prank(alice);
        farm.deposit(1);
    }

    function test_RevertWhen_WithdrawCallerIsNotDepositor() public {
        vm.expectRevert(abi.encodeWithSelector(IMockFarm.MockFarm__CallerNotDepositor.selector, alice));
        vm.prank(alice);
        farm.withdraw(1);
    }

    function test_RevertWhen_ClaimCallerIsNotDepositor() public {
        vm.expectRevert(abi.encodeWithSelector(IMockFarm.MockFarm__CallerNotDepositor.selector, alice));
        vm.prank(alice);
        farm.claim();
    }

    function test_RevertWhen_EmergencyWithdrawCallerIsNotDepositor() public {
        vm.expectRevert(abi.encodeWithSelector(IMockFarm.MockFarm__CallerNotDepositor.selector, alice));
        vm.prank(alice);
        farm.emergencyWithdraw();
    }

    function test_RevertWhen_DepositAmountIsZero() public {
        vm.prank(owner);
        farm.addDepositor(alice);

        vm.expectRevert(IMockFarm.MockFarm__ZeroAmount.selector);
        vm.prank(alice);
        farm.deposit(0);
    }

    function test_RevertWhen_WithdrawAmountIsZero() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);

        vm.expectRevert(IMockFarm.MockFarm__ZeroAmount.selector);
        vm.prank(alice);
        farm.withdraw(0);
    }

    function test_RevertWhen_FundRewardsAmountIsZero() public {
        vm.expectRevert(IMockFarm.MockFarm__ZeroAmount.selector);
        vm.prank(owner);
        farm.fundRewards(0);
    }

    function test_RevertWhen_EmergencyWithdrawPrincipalIsZero() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        farm.withdraw(CRUISE_PRINCIPAL);

        assertEq(farm.principalOf(alice), 0);
        assertEq(farm.accrued(alice), CRUISE_30_DAYS);

        vm.expectRevert(IMockFarm.MockFarm__ZeroAmount.selector);
        vm.prank(alice);
        farm.emergencyWithdraw();

        assertEq(farm.accrued(alice), CRUISE_30_DAYS);
    }

    function test_RevertWhen_WithdrawExceedsPrincipal() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMockFarm.MockFarm__InsufficientPrincipal.selector, CRUISE_PRINCIPAL, CRUISE_PRINCIPAL + 1
            )
        );
        vm.prank(alice);
        farm.withdraw(CRUISE_PRINCIPAL + 1);
    }

    function test_FundRewardsIncreasesReserveOnly() public {
        vm.startPrank(owner);
        usdc.approve(address(farm), 100);
        vm.expectEmit(address(farm));
        emit MockFarm.RewardsFunded(owner, 100, 100);
        farm.fundRewards(100);
        vm.stopPrank();

        assertEq(farm.rewardReserve(), 100);
        assertEq(farm.totalPrincipal(), 0);
        assertEq(usdc.balanceOf(address(farm)), 100);
        assertEq(usdc.allowance(owner, address(farm)), 0);
    }

    function test_WarpAccruesCruiseExample() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);

        vm.warp(block.timestamp + 30 days);

        assertEq(farm.accrued(alice), CRUISE_30_DAYS);
        assertEq(farm.principalOf(alice), CRUISE_PRINCIPAL);
    }

    function test_AdvanceTimeAccruesCruiseExample() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        uint256 start = block.timestamp;

        vm.prank(owner);
        demo.advanceTime(30 days);

        assertEq(block.timestamp, start);
        assertEq(demo.currentTime(), start + 30 days);
        assertEq(farm.accrued(alice), CRUISE_30_DAYS);
    }

    function test_ProductionClockFollowsWarpAndCannotAdvance() public {
        DriverClock production = new DriverClock();
        MockFarm timed = new MockFarm(usdc, production, APR, owner);
        _deposit(timed, alice, CRUISE_PRINCIPAL);

        vm.warp(block.timestamp + 30 days);

        assertEq(timed.accrued(alice), CRUISE_30_DAYS);

        (bool ok, bytes memory data) = address(production).call(abi.encodeWithSignature("advanceTime(uint256)", 1));
        assertFalse(ok);
        assertEq(data.length, 0);
        assertEq(timed.accrued(alice), CRUISE_30_DAYS);
    }

    function test_OneUsdcAccruesFiftyThousandBaseUnitsInOneYear() public {
        _deposit(farm, alice, ONE_USDC);

        vm.warp(block.timestamp + 365 days);

        assertEq(farm.accrued(alice), 50_000);
    }

    function test_AccrualFloorsPartialBaseUnits() public {
        _deposit(farm, alice, ONE_USDC);

        vm.warp(block.timestamp + 1 days);

        assertEq(farm.accrued(alice), 136);
    }

    function test_DriftAprAccruesWithoutOverflow() public {
        MockFarm drift = new MockFarm(usdc, demo, 16_000, owner);
        _deposit(drift, alice, 30_000 * 10 ** 6);

        vm.warp(block.timestamp + 30 days);

        assertEq(drift.accrued(alice), 3_945_205_479);
    }

    function test_AccruedIsZeroWithNoPrincipal() public view {
        assertEq(farm.accrued(alice), 0);
    }

    function test_AccruedIsNotCappedByReserve() public {
        _fund(1);
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);

        assertEq(farm.rewardReserve(), 1);
        assertEq(farm.accrued(alice), CRUISE_30_DAYS);
    }

    function test_DepositDoesNotAccrueTheNewPrincipalBackward() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);

        _mintAndDeposit(farm, alice, CRUISE_PRINCIPAL);

        assertEq(farm.principalOf(alice), CRUISE_PRINCIPAL * 2);
        assertEq(farm.accrued(alice), CRUISE_30_DAYS);
    }

    function test_ClaimReturnsZeroWhenNothingIsOwed() public {
        _fund(1_000 * 10 ** 6);
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.recordLogs();
        vm.prank(alice);
        uint256 paid = farm.claim();

        assertEq(paid, 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(farm.accrued(alice), 0);
        assertEq(farm.principalOf(alice), CRUISE_PRINCIPAL);
        assertEq(farm.rewardReserve(), 1_000 * 10 ** 6);
        assertEq(usdc.balanceOf(alice), balanceBefore);
    }

    function test_ClaimPaysCappedReserveAndLeavesUnpaid() public {
        _fund(100);
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.expectEmit(address(farm));
        emit IMockFarm.RewardsClaimed(alice, 100, CRUISE_30_DAYS - 100);

        vm.prank(alice);
        uint256 paid = farm.claim();

        assertEq(paid, 100);
        assertEq(farm.accrued(alice), CRUISE_30_DAYS - 100);
        assertEq(farm.rewardReserve(), 0);
        assertEq(farm.principalOf(alice), CRUISE_PRINCIPAL);
        assertEq(farm.totalPrincipal(), CRUISE_PRINCIPAL);
        assertEq(usdc.balanceOf(alice), balanceBefore + 100);
        assertEq(usdc.balanceOf(address(farm)), CRUISE_PRINCIPAL);
    }

    function test_ClaimReturnsZeroWhenReserveIsEmptyAndRewardsRemain() public {
        _fund(100);
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        farm.claim();
        uint256 unpaid = farm.accrued(alice);
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 paid = farm.claim();

        assertEq(paid, 0);
        assertGt(unpaid, 0);
        assertEq(farm.accrued(alice), unpaid);
        assertEq(farm.rewardReserve(), 0);
        assertEq(farm.principalOf(alice), CRUISE_PRINCIPAL);
        assertEq(usdc.balanceOf(alice), balanceBefore);
    }

    function test_SecondDepositorClaimDoesNotSpendFirstPrincipal() public {
        _fund(1_000 * 10 ** 6);
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        _deposit(farm, bob, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        uint256 aliceUsdc = usdc.balanceOf(alice);

        vm.prank(bob);
        uint256 paid = farm.claim();

        assertEq(paid, CRUISE_30_DAYS);
        assertEq(farm.principalOf(alice), CRUISE_PRINCIPAL);
        assertEq(farm.principalOf(bob), CRUISE_PRINCIPAL);
        assertEq(farm.totalPrincipal(), CRUISE_PRINCIPAL * 2);
        assertEq(farm.accrued(alice), CRUISE_30_DAYS);
        assertEq(farm.accrued(bob), 0);
        assertEq(usdc.balanceOf(alice), aliceUsdc);
        assertEq(farm.rewardReserve(), 1_000 * 10 ** 6 - CRUISE_30_DAYS);
        assertEq(usdc.balanceOf(address(farm)), CRUISE_PRINCIPAL * 2 + farm.rewardReserve());
    }

    function test_WithdrawStoresRewardsThenReturnsPrincipal() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        uint256 balanceBefore = usdc.balanceOf(alice);
        uint256 half = CRUISE_PRINCIPAL / 2;

        vm.expectEmit(address(farm));
        emit MockFarm.Withdrawn(alice, half, half);

        vm.prank(alice);
        farm.withdraw(half);

        assertEq(farm.principalOf(alice), half);
        assertEq(farm.accrued(alice), CRUISE_30_DAYS);
        assertEq(usdc.balanceOf(alice), balanceBefore + half);
        assertEq(farm.rewardReserve(), 0);

        vm.warp(block.timestamp + 30 days);

        assertEq(farm.accrued(alice), CRUISE_30_DAYS + 30_821_917);
    }

    function test_ClaimPaysStoredRewardsPlusNewRewards() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        farm.withdraw(CRUISE_PRINCIPAL / 2);
        vm.warp(block.timestamp + 30 days);

        uint256 expected = CRUISE_30_DAYS + 30_821_917;
        _fund(expected);

        vm.prank(alice);
        uint256 paid = farm.claim();

        assertEq(paid, expected);
        assertEq(farm.accrued(alice), 0);
    }

    function test_ClaimPaysUnpaidRemainderPlusNewRewards() public {
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        _fund(100);
        vm.prank(alice);
        farm.claim();

        uint256 unpaid = CRUISE_30_DAYS - 100;
        _fund(unpaid + CRUISE_30_DAYS);
        vm.warp(block.timestamp + 30 days);

        vm.prank(alice);
        uint256 paid = farm.claim();

        assertEq(paid, unpaid + CRUISE_30_DAYS);
    }

    function test_EmergencyWithdrawForfeitsStoredRewards() public {
        _fund(1_000 * 10 ** 6);
        _deposit(farm, alice, CRUISE_PRINCIPAL);
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        farm.withdraw(1);
        uint256 principalLeft = CRUISE_PRINCIPAL - 1;
        uint256 reserveBefore = farm.rewardReserve();
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.expectEmit(address(farm));
        emit IMockFarm.EmergencyWithdrawn(alice, principalLeft, CRUISE_30_DAYS);

        vm.prank(alice);
        uint256 returned = farm.emergencyWithdraw();

        assertEq(returned, principalLeft);
        assertEq(farm.principalOf(alice), 0);
        assertEq(farm.totalPrincipal(), 0);
        assertEq(farm.accrued(alice), 0);
        assertEq(farm.rewardReserve(), reserveBefore);
        assertEq(usdc.balanceOf(alice), balanceBefore + principalLeft);
        assertEq(usdc.balanceOf(address(farm)), reserveBefore);
    }

    function test_EmergencyWithdrawWorksWhenClockMovesBackward() public {
        SettableDriverClock clock = new SettableDriverClock();
        MockFarm timed = new MockFarm(usdc, clock, APR, owner);
        uint256 start = 1_000_000;
        clock.setTime(start);
        _deposit(timed, alice, CRUISE_PRINCIPAL);
        clock.setTime(start + 30 days);
        assertEq(timed.accrued(alice), CRUISE_30_DAYS);

        clock.setTime(start - 1);
        assertEq(timed.accrued(alice), 0);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(alice);
        timed.claim();

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(alice);
        timed.withdraw(1);

        uint256 reserveBefore = timed.rewardReserve();
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 returned = timed.emergencyWithdraw();

        assertEq(returned, CRUISE_PRINCIPAL);
        assertEq(timed.principalOf(alice), 0);
        assertEq(timed.accrued(alice), 0);
        assertEq(timed.rewardReserve(), reserveBefore);
        assertEq(usdc.balanceOf(alice), balanceBefore + CRUISE_PRINCIPAL);
    }

    function test_EmergencyWithdrawWorksWhenClockReverts() public {
        HaltingDriverClock clock = new HaltingDriverClock();
        MockFarm timed = new MockFarm(usdc, clock, APR, owner);
        uint256 start = 1_000_000;
        clock.setTime(start);
        _deposit(timed, alice, CRUISE_PRINCIPAL);
        clock.setTime(start + 30 days);
        assertEq(timed.accrued(alice), CRUISE_30_DAYS);
        clock.halt();

        vm.expectRevert(HaltingDriverClock.HaltingDriverClock__Halted.selector);
        vm.prank(alice);
        timed.claim();

        vm.expectRevert(HaltingDriverClock.HaltingDriverClock__Halted.selector);
        vm.prank(alice);
        timed.withdraw(1);

        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 returned = timed.emergencyWithdraw();

        assertEq(returned, CRUISE_PRINCIPAL);
        assertEq(timed.principalOf(alice), 0);
        assertEq(timed.totalPrincipal(), 0);
        assertEq(timed.accrued(alice), 0);
        assertEq(timed.rewardReserve(), 0);
        assertEq(usdc.balanceOf(alice), balanceBefore + CRUISE_PRINCIPAL);
    }

    function test_DepositAfterEmergencyDoesNotEarnTheForfeitedPeriod() public {
        SettableDriverClock clock = new SettableDriverClock();
        MockFarm timed = new MockFarm(usdc, clock, APR, owner);
        uint256 start = 1_000_000;
        clock.setTime(start);
        _deposit(timed, alice, CRUISE_PRINCIPAL);
        clock.setTime(start + 30 days);
        vm.prank(alice);
        timed.emergencyWithdraw();

        clock.setTime(start + 60 days);
        _mintAndDeposit(timed, alice, CRUISE_PRINCIPAL);

        assertEq(timed.accrued(alice), 0);
        assertEq(timed.principalOf(alice), CRUISE_PRINCIPAL);
    }

    function test_DirectTransferIsNotReserveOrPrincipal() public {
        vm.prank(owner);
        assertTrue(usdc.transfer(address(farm), 123));

        assertEq(farm.rewardReserve(), 0);
        assertEq(farm.totalPrincipal(), 0);
        assertEq(usdc.balanceOf(address(farm)), 123);
    }

    function test_RenounceBlocksFundingAndDepositsStillWork() public {
        vm.prank(owner);
        farm.addDepositor(alice);
        vm.prank(owner);
        farm.renounceOwnership();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        farm.fundRewards(1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        farm.addDepositor(bob);

        _mintAndDeposit(farm, alice, ONE_USDC);
        assertEq(farm.principalOf(alice), ONE_USDC);
    }

    function _fund(uint256 amount) internal {
        vm.startPrank(owner);
        usdc.approve(address(farm), amount);
        farm.fundRewards(amount);
        vm.stopPrank();
    }

    function _deposit(MockFarm target, address account, uint256 amount) internal {
        vm.prank(owner);
        target.addDepositor(account);
        _mintAndDeposit(target, account, amount);
    }

    function _mintAndDeposit(MockFarm target, address account, uint256 amount) internal {
        vm.prank(owner);
        usdc.mint(account, amount);
        vm.startPrank(account);
        usdc.approve(address(target), amount);
        target.deposit(amount);
        vm.stopPrank();
    }
}
