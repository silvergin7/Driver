// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../src/TreasuryFund.sol";

contract CruiseControlFuzzTest is Test {
    uint256 internal constant APR = 500;
    uint256 internal constant MAX_AMOUNT = 1e15;
    uint256 internal constant MAX_ELAPSED = 365 days;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    MockFarm internal farmA;
    MockFarm internal farmB;
    CruiseControl internal fund;
    address internal owner = makeAddr("owner");

    function setUp() public {
        usdc = new MockUSDC(owner);
        clock = new DemoDriverClock(owner);
        DriverToken token = new DriverToken(owner);
        TaxSplitter splitter = new TaxSplitter(usdc, owner);
        OfficialPool pool = new OfficialPool(token, usdc, splitter, owner, 100);
        farmA = new MockFarm(usdc, clock, APR, owner);
        farmB = new MockFarm(usdc, clock, APR, owner);
        fund = new CruiseControl(usdc, clock, splitter, pool, _pair(), owner);

        vm.startPrank(owner);
        usdc.mint(owner, 10 * MAX_AMOUNT);
        usdc.approve(address(fund), type(uint256).max);
        farmA.addDepositor(address(fund));
        farmB.addDepositor(address(fund));
        vm.stopPrank();
    }

    function testFuzz_SupplyCreditsIdleExactly(uint256 amount) public {
        amount = bound(amount, 1, MAX_AMOUNT);

        vm.prank(owner);
        fund.supply(amount);

        assertEq(fund.idle(), amount);
        assertEq(fund.value(), amount);
    }

    function testFuzz_SwitchMovesPrincipalExactly(uint256 amount) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        _deployAll(amount);

        vm.prank(owner);
        fund.setStrategy(farmB);

        assertEq(farmA.principalOf(address(fund)), 0);
        assertEq(farmB.principalOf(address(fund)), amount);
        assertEq(fund.principal(), amount);
        assertEq(fund.idle(), 0);
        assertEq(fund.value(), amount);
    }

    function testFuzz_ValueEqualsIdlePlusPrincipal(uint256 supplied, uint256 deposited) public {
        supplied = bound(supplied, 2, MAX_AMOUNT);
        deposited = bound(deposited, 1, supplied - 1);

        vm.startPrank(owner);
        fund.setStrategy(farmA);
        fund.supply(supplied);
        fund.deposit(deposited);
        vm.stopPrank();

        assertEq(fund.idle(), supplied - deposited);
        assertEq(fund.principal(), deposited);
        assertEq(fund.value(), fund.idle() + fund.principal());
    }

    function testFuzz_ClaimedRewardIncreasesHeldRewardsOnly(uint256 amount, uint256 elapsed, uint256 warpBy) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 2, MAX_ELAPSED);
        warpBy = bound(warpBy, 1, elapsed - 1);
        uint256 advanceBy = elapsed - warpBy;
        uint256 owed = _owed(amount, elapsed);
        vm.assume(owed != 0);
        _deployAll(amount);

        vm.warp(block.timestamp + warpBy);
        vm.startPrank(owner);
        clock.advanceTime(advanceBy);
        usdc.approve(address(farmA), owed + 1);
        farmA.fundRewards(owed + 1);
        fund.setStrategy(farmB);
        vm.stopPrank();

        assertEq(fund.heldRewards(), owed);
        assertEq(fund.idle(), 0);
        assertEq(fund.value(), amount);
    }

    function testFuzz_DonationDoesNotChangeLedgers(uint256 amount, uint256 elapsed, uint256 donated) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        elapsed = bound(elapsed, 1, MAX_ELAPSED);
        donated = bound(donated, 1, MAX_AMOUNT);
        uint256 owed = _owed(amount, elapsed);
        vm.assume(owed != 0);
        _deployAll(amount);

        vm.startPrank(owner);
        clock.advanceTime(elapsed);
        usdc.approve(address(farmA), owed);
        farmA.fundRewards(owed);
        fund.setStrategy(farmB);
        vm.stopPrank();

        uint256 idleBefore = fund.idle();
        uint256 heldBefore = fund.heldRewards();
        uint256 valueBefore = fund.value();
        assertEq(heldBefore, owed);

        vm.prank(owner);
        usdc.mint(address(this), donated);
        assertTrue(usdc.transfer(address(fund), donated));

        assertEq(fund.idle(), idleBefore);
        assertEq(fund.heldRewards(), heldBefore);
        assertEq(fund.value(), valueBefore);
    }

    function testFuzz_TimeSkipDoesNotChangeValue(uint256 amount, uint256 warpBy, uint256 advanceBy) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        warpBy = bound(warpBy, 1, MAX_ELAPSED);
        advanceBy = bound(advanceBy, 1, MAX_ELAPSED);
        _deployAll(amount);
        uint256 valueBefore = fund.value();

        vm.warp(block.timestamp + warpBy);
        vm.prank(owner);
        clock.advanceTime(advanceBy);

        assertEq(fund.value(), valueBefore);
        assertEq(fund.pendingRewards(), _owed(amount, warpBy + advanceBy));
    }

    function testFuzz_UnlistedAddressCannotBecomeTheStrategy(address candidate) public {
        vm.assume(candidate != address(0) && candidate != address(farmA) && candidate != address(farmB));

        vm.expectRevert(abi.encodeWithSelector(TreasuryFund.TreasuryFund__StrategyNotAllowed.selector, candidate));
        vm.prank(owner);
        fund.setStrategy(IMockFarm(candidate));
    }

    function _deployAll(uint256 amount) private {
        vm.startPrank(owner);
        fund.setStrategy(farmA);
        fund.supply(amount);
        fund.deposit(amount);
        vm.stopPrank();
    }

    function _owed(uint256 amount, uint256 elapsed) private pure returns (uint256 owed) {
        owed = Math.mulDiv(amount, APR * elapsed, BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    function _pair() private view returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](2);
        farms[0] = farmA;
        farms[1] = farmB;
    }
}
