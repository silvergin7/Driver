// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {IOfficialPool} from "../../src/interfaces/IOfficialPool.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../src/TreasuryFund.sol";

contract CruiseControlTest is Test {
    uint256 internal constant APR = 500;
    uint256 internal constant YEAR = 365 days;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    MockFarm internal farmA;
    MockFarm internal farmB;
    CruiseControl internal fund;
    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");
    address internal nextOwner = makeAddr("nextOwner");

    function setUp() public {
        usdc = new MockUSDC(owner);
        clock = new DemoDriverClock(owner);
        DriverToken token = new DriverToken(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, 100);
        farmA = new MockFarm(usdc, clock, APR, owner);
        farmB = new MockFarm(usdc, clock, APR, owner);
        fund = new CruiseControl(usdc, clock, splitter, pool, _pair(farmA, farmB), owner);

        vm.startPrank(owner);
        usdc.mint(owner, 2_000_000 * 10 ** 6);
        usdc.approve(address(fund), type(uint256).max);
        farmA.addDepositor(address(fund));
        farmB.addDepositor(address(fund));
        vm.stopPrank();
    }

    function test_ConstructorStoresConfigAndListsFarms() public view {
        assertEq(address(fund.i_usdc()), address(usdc));
        assertEq(address(fund.i_clock()), address(clock));
        assertEq(address(fund.i_taxSplitter()), address(splitter));
        assertEq(address(fund.i_pool()), address(pool));
        assertEq(uint256(fund.i_fundId()), uint256(TaxSplitter.FundId.Fund1));
        assertEq(fund.owner(), owner);
        assertEq(fund.strategyCount(), 2);
        assertEq(address(fund.strategyAt(0)), address(farmA));
        assertEq(address(fund.strategyAt(1)), address(farmB));
        assertTrue(fund.isStrategy(address(farmA)));
        assertTrue(fund.isStrategy(address(farmB)));
        assertFalse(fund.isStrategy(stranger));
        assertEq(address(fund.activeFarm()), address(0));
        assertEq(fund.idle(), 0);
        assertEq(fund.heldRewards(), 0);
        assertEq(fund.principal(), 0);
        assertEq(fund.value(), 0);
        assertEq(fund.pendingRewards(), 0);
    }

    function test_ConstructorEmitsStrategyListed() public {
        vm.expectEmit(true, false, false, true);
        emit TreasuryFund.StrategyListed(address(farmA));
        vm.expectEmit(true, false, false, true);
        emit TreasuryFund.StrategyListed(address(farmB));
        new CruiseControl(usdc, clock, splitter, pool, _pair(farmA, farmB), owner);
    }

    function test_RevertWhen_UsdcIsZeroAddress() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAddress.selector);
        new CruiseControl(MockUSDC(address(0)), clock, splitter, pool, _pair(farmA, farmB), owner);
    }

    function test_RevertWhen_ClockIsZeroAddress() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAddress.selector);
        new CruiseControl(usdc, IDriverClock(address(0)), splitter, pool, _pair(farmA, farmB), owner);
    }

    function test_RevertWhen_SplitterIsZeroAddress() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAddress.selector);
        new CruiseControl(usdc, clock, TaxSplitter(address(0)), pool, _pair(farmA, farmB), owner);
    }

    function test_RevertWhen_PoolIsZeroAddress() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAddress.selector);
        new CruiseControl(usdc, clock, splitter, IOfficialPool(address(0)), _pair(farmA, farmB), owner);
    }

    function test_RevertWhen_OwnerIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new CruiseControl(usdc, clock, splitter, pool, _pair(farmA, farmB), address(0));
    }

    function test_RevertWhen_FarmListIsEmpty() public {
        IMockFarm[] memory farms = new IMockFarm[](0);
        vm.expectRevert(TreasuryFund.TreasuryFund__NoFarms.selector);
        new CruiseControl(usdc, clock, splitter, pool, farms, owner);
    }

    function test_RevertWhen_FarmIsZeroAddress() public {
        IMockFarm[] memory farms = new IMockFarm[](1);
        farms[0] = IMockFarm(address(0));
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAddress.selector);
        new CruiseControl(usdc, clock, splitter, pool, farms, owner);
    }

    function test_RevertWhen_FarmIsDuplicated() public {
        IMockFarm[] memory farms = new IMockFarm[](2);
        farms[0] = farmA;
        farms[1] = farmA;
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryFund.TreasuryFund__StrategyAlreadyListed.selector, address(farmA))
        );
        new CruiseControl(usdc, clock, splitter, pool, farms, owner);
    }

    function test_RevertWhen_FarmTokenMismatches() public {
        MockUSDC other = new MockUSDC(owner);
        MockFarm bad = new MockFarm(other, clock, APR, owner);
        IMockFarm[] memory farms = new IMockFarm[](1);
        farms[0] = bad;
        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__FarmTokenMismatch.selector, address(bad)));
        new CruiseControl(usdc, clock, splitter, pool, farms, owner);
    }

    function test_RevertWhen_FarmClockMismatches() public {
        DemoDriverClock other = new DemoDriverClock(owner);
        MockFarm bad = new MockFarm(usdc, other, APR, owner);
        IMockFarm[] memory farms = new IMockFarm[](1);
        farms[0] = bad;
        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__FarmClockMismatch.selector, address(bad)));
        new CruiseControl(usdc, clock, splitter, pool, farms, owner);
    }

    function test_SupplyCreditsIdleFromCaller() public {
        uint256 amount = 1_000 * 10 ** 6;
        vm.expectEmit(address(fund));
        emit TreasuryFund.CapitalSupplied(owner, amount, amount);
        vm.prank(owner);
        fund.supply(amount);

        assertEq(fund.idle(), amount);
        assertEq(fund.value(), amount);
        assertEq(usdc.balanceOf(address(fund)), amount);
        assertEq(usdc.balanceOf(owner), 2_000_000 * 10 ** 6 - amount);
    }

    function test_SecondSupplyAddsToIdle() public {
        uint256 first = 100 * 10 ** 6;
        uint256 second = 40 * 10 ** 6;
        vm.startPrank(owner);
        fund.supply(first);
        assertEq(fund.idle(), first);
        assertEq(fund.value(), first);
        fund.supply(second);
        vm.stopPrank();

        assertEq(fund.idle(), first + second);
        assertEq(fund.value(), first + second);
    }

    function test_SupplyPullsFromTheCurrentOwner() public {
        uint256 amount = 40 * 10 ** 6;
        vm.prank(owner);
        fund.transferOwnership(nextOwner);
        vm.prank(nextOwner);
        fund.acceptOwnership();
        vm.prank(owner);
        usdc.mint(nextOwner, amount);
        vm.prank(nextOwner);
        usdc.approve(address(fund), amount);

        vm.prank(nextOwner);
        fund.supply(amount);

        assertEq(fund.idle(), amount);
        assertEq(usdc.balanceOf(nextOwner), 0);
        assertEq(usdc.balanceOf(owner), 2_000_000 * 10 ** 6);
    }

    function test_RevertWhen_SupplyAmountIsZero() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
        vm.prank(owner);
        fund.supply(0);
    }

    function test_RevertWhen_SupplyCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        fund.supply(1);
    }

    function test_SetStrategyStoresTheFirstFarm() public {
        vm.expectEmit(address(fund));
        emit TreasuryFund.StrategySet(address(0), address(farmA), 0, 0);
        vm.prank(owner);
        fund.setStrategy(farmA);

        assertEq(address(fund.activeFarm()), address(farmA));
        assertEq(fund.heldRewards(), 0);
        assertEq(fund.principal(), 0);
    }

    function test_RevertWhen_StrategyIsZeroAddress() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAddress.selector);
        vm.prank(owner);
        fund.setStrategy(IMockFarm(address(0)));
    }

    function test_RevertWhen_StrategyIsNotListed() public {
        MockFarm other = new MockFarm(usdc, clock, APR, owner);
        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__StrategyNotAllowed.selector, address(other)));
        vm.prank(owner);
        fund.setStrategy(other);
    }

    function test_RevertWhen_StrategyIsUnchanged() public {
        vm.prank(owner);
        fund.setStrategy(farmA);
        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__StrategyUnchanged.selector, address(farmA)));
        vm.prank(owner);
        fund.setStrategy(farmA);
    }

    function test_RevertWhen_SetStrategyCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        fund.setStrategy(farmA);
    }

    function test_DepositMovesIdleToTheActiveFarm() public {
        uint256 amount = 1_500 * 10 ** 6;
        vm.startPrank(owner);
        fund.setStrategy(farmA);
        fund.supply(amount);
        vm.expectEmit(true, true, true, true, address(fund));
        emit TreasuryFund.CapitalDeployed(address(farmA), amount, 0);
        fund.deposit(amount);
        vm.stopPrank();

        assertEq(fund.idle(), 0);
        assertEq(fund.principal(), amount);
        assertEq(fund.value(), amount);
        assertEq(farmA.principalOf(address(fund)), amount);
        assertEq(usdc.balanceOf(address(fund)), 0);
        assertEq(usdc.allowance(address(fund), address(farmA)), 0);
    }

    function test_DepositEmitsTheRemainingIdle() public {
        uint256 supplied = 1_500 * 10 ** 6;
        uint256 deposited = 400 * 10 ** 6;
        uint256 remaining = supplied - deposited;
        vm.startPrank(owner);
        fund.setStrategy(farmA);
        fund.supply(supplied);
        vm.expectEmit(true, true, true, true, address(fund));
        emit TreasuryFund.CapitalDeployed(address(farmA), deposited, remaining);
        fund.deposit(deposited);
        vm.stopPrank();

        assertEq(fund.idle(), remaining);
        assertEq(fund.principal(), deposited);
        assertEq(fund.value(), supplied);
    }

    function test_RevertWhen_DepositAmountIsZero() public {
        vm.startPrank(owner);
        fund.setStrategy(farmA);
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
        fund.deposit(0);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositHasNoActiveFarm() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        vm.prank(owner);
        fund.deposit(1);
    }

    function test_RevertWhen_DepositExceedsIdle() public {
        vm.startPrank(owner);
        fund.setStrategy(farmA);
        fund.supply(10);
        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__InsufficientIdle.selector, 10, 11));
        fund.deposit(11);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositCallerIsNotOwner() public {
        vm.prank(owner);
        fund.setStrategy(farmA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        fund.deposit(1);
    }

    function test_SwitchWithAShortReserveCreditsTheClaimedAmount() public {
        uint256 amount = 1_000 * 10 ** 6;
        uint256 elapsed = YEAR;
        uint256 owed = Math.mulDiv(amount, APR * elapsed, 10_000 * YEAR);
        assertGt(owed, 1);

        vm.startPrank(owner);
        fund.setStrategy(farmA);
        fund.supply(amount);
        fund.deposit(amount);
        clock.advanceTime(elapsed);
        usdc.approve(address(farmA), 1);
        farmA.fundRewards(1);
        vm.stopPrank();

        vm.expectEmit(address(fund));
        emit TreasuryFund.StrategySet(address(farmA), address(farmB), amount, 1);
        vm.prank(owner);
        fund.setStrategy(farmB);

        assertEq(fund.heldRewards(), 1);
        assertEq(farmA.accrued(address(fund)), owed - 1);
        assertEq(farmA.principalOf(address(fund)), 0);
        assertEq(farmB.principalOf(address(fund)), amount);
        assertEq(fund.idle(), 0);
        assertEq(fund.principal(), amount);
        assertEq(fund.value(), amount);
        assertEq(fund.pendingRewards(), 0);
        assertEq(usdc.balanceOf(address(fund)), 1);
        assertEq(usdc.allowance(address(fund), address(farmB)), 0);
    }

    function test_SwitchWithZeroPrincipalClaimsNothing() public {
        vm.prank(owner);
        fund.setStrategy(farmA);
        vm.prank(owner);
        clock.advanceTime(30 days);

        vm.expectCall(address(farmA), abi.encodeCall(IMockFarm.claim, ()), 1);
        vm.expectCall(address(farmA), abi.encodeWithSelector(IMockFarm.withdraw.selector), 0);
        vm.expectEmit(address(fund));
        emit TreasuryFund.StrategySet(address(farmA), address(farmB), 0, 0);
        vm.prank(owner);
        fund.setStrategy(farmB);

        assertEq(address(fund.activeFarm()), address(farmB));
        assertEq(fund.heldRewards(), 0);
        assertEq(fund.idle(), 0);
        assertEq(fund.principal(), 0);
        assertEq(farmA.principalOf(address(fund)), 0);
        assertEq(farmB.principalOf(address(fund)), 0);
    }

    function test_SecondSwitchAddsClaimedRewards() public {
        uint256 amount = 15_000 * 10 ** 6;
        uint256 firstElapsed = 30 days;
        uint256 secondElapsed = 60 days;
        uint256 firstClaim = Math.mulDiv(amount, APR * firstElapsed, 10_000 * YEAR);
        uint256 secondClaim = Math.mulDiv(amount, APR * secondElapsed, 10_000 * YEAR);
        assertGt(firstClaim, 0);
        assertGt(secondClaim, 0);

        vm.startPrank(owner);
        usdc.approve(address(farmA), firstClaim);
        farmA.fundRewards(firstClaim);
        usdc.approve(address(farmB), secondClaim);
        farmB.fundRewards(secondClaim);
        fund.setStrategy(farmA);
        fund.supply(amount);
        fund.deposit(amount);
        clock.advanceTime(firstElapsed);
        fund.setStrategy(farmB);
        clock.advanceTime(secondElapsed);
        fund.setStrategy(farmA);
        vm.stopPrank();

        assertEq(fund.heldRewards(), firstClaim + secondClaim);
        assertEq(fund.principal(), amount);
        assertEq(address(fund.activeFarm()), address(farmA));
    }

    function test_DirectTransferStaysOutOfTheLedgers() public {
        vm.prank(owner);
        usdc.transfer(address(fund), 7);

        assertEq(usdc.balanceOf(address(fund)), 7);
        assertEq(fund.idle(), 0);
        assertEq(fund.heldRewards(), 0);
        assertEq(fund.value(), 0);
    }

    function test_DemoClockSkipLeavesValueUnchanged() public {
        uint256 amount = 15_000 * 10 ** 6;
        uint256 elapsed = 30 days;
        vm.startPrank(owner);
        fund.setStrategy(farmA);
        fund.supply(amount);
        fund.deposit(amount);
        clock.advanceTime(elapsed);
        vm.stopPrank();

        assertEq(fund.idle(), 0);
        assertEq(fund.heldRewards(), 0);
        assertEq(fund.principal(), amount);
        assertEq(fund.value(), amount);
        assertEq(fund.pendingRewards(), Math.mulDiv(amount, APR * elapsed, 10_000 * YEAR));
    }

    function _pair(MockFarm first, MockFarm second) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](2);
        farms[0] = first;
        farms[1] = second;
    }
}
