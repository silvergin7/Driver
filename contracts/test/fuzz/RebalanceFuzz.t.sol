// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
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

contract RebalanceFuzzTest is Test {
    uint256 internal constant MAX_SHARE = 1_000_000 * 10 ** 6;
    uint256 internal constant SEED_DVR = 500_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    RoundSchedule internal schedule;

    function setUp() public {
        usdc = new MockUSDC(address(this));
        DriverToken token = new DriverToken(address(this));
        clock = new DemoDriverClock(address(this));
        splitter = new TaxSplitter(usdc, address(this));
        pool = new OfficialPool(token, usdc, splitter, address(this), 100);
        schedule = new RoundSchedule(clock, 30 days);
        splitter.setPool(address(pool));
        token.mint(address(this), SEED_DVR);
        usdc.mint(address(this), type(uint128).max);
        token.approve(address(pool), SEED_DVR);
        usdc.approve(address(pool), SEED_USDC);
        pool.addLiquidity(SEED_DVR, SEED_USDC);
    }

    function testFuzz_ShareBounds(uint256 share1, uint256 share2) public {
        share1 = bound(share1, 0, MAX_SHARE);
        share2 = bound(share2, 0, MAX_SHARE);
        if (share1 == 0 || share2 == 0) {
            vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
            new CruiseControl(usdc, clock, schedule, splitter, pool, share1, share2, _farms(), address(this));
            return;
        }
        if (share1 <= share2) {
            vm.expectRevert(
                abi.encodeWithSelector(TreasuryFund.TreasuryFund__Fund1ShareNotLarger.selector, share1, share2)
            );
            new CruiseControl(usdc, clock, schedule, splitter, pool, share1, share2, _farms(), address(this));
            return;
        }

        (CruiseControl cruise, DegenDriver degen) = _pair(share1, share2);
        assertEq(cruise.i_fund1Usdc(), share1);
        assertEq(cruise.i_fund2Usdc(), share2);
        assertEq(degen.i_fund1Usdc(), share1);
        assertEq(degen.i_fund2Usdc(), share2);
    }

    function testFuzz_RebalanceMatchesTheFloor(uint256 share1, uint256 share2, uint256 fund1Value, uint256 fund2Value)
        public
    {
        (share1, share2) = _shares(share1, share2);
        fund1Value = bound(fund1Value, 0, MAX_SHARE);
        fund2Value = bound(fund2Value, 0, MAX_SHARE);
        uint256 expected = _move(share2, fund2Value, share1, fund1Value);

        (CruiseControl cruise, DegenDriver degen) = _pair(share1, share2);
        _supply(cruise, fund1Value);
        _supply(degen, fund2Value);
        cruise.setFund2(degen);
        uint256 sum = cruise.value() + degen.value();

        (uint256 read1, uint256 read2, uint256 readAmount) = degen.rebalanceAmount();
        assertEq(read1, fund1Value);
        assertEq(read2, fund2Value);
        assertEq(readAmount, expected);

        clock.advanceTime(30 days);
        degen.harvest(0);

        (,, uint256 stored1, uint256 stored2, uint256 moved) = degen.lastRebalance();
        assertEq(stored1, fund1Value);
        assertEq(stored2, fund2Value);
        assertEq(moved, expected);
        assertEq(cruise.value(), fund1Value + expected);
        assertEq(degen.value(), fund2Value - expected);
        assertEq(cruise.value() + degen.value(), sum);
    }

    function testFuzz_TopUpMatchesTheFloor(
        uint256 share1,
        uint256 share2,
        uint256 fund1Value,
        uint256 fund2Value,
        uint256 amount
    ) public {
        (share1, share2) = _shares(share1, share2);
        fund1Value = bound(fund1Value, 0, MAX_SHARE);
        fund2Value = bound(fund2Value, 0, MAX_SHARE);
        uint256 cap = _move(share1, fund1Value, share2, fund2Value);
        amount = bound(amount, 0, cap + 1);

        (CruiseControl cruise, DegenDriver degen) = _pair(share1, share2);
        _supply(cruise, fund1Value);
        _supply(degen, fund2Value);
        cruise.setFund2(degen);

        (uint256 read1, uint256 read2, uint256 readCap) = cruise.topUpCap();
        assertEq(read1, fund1Value);
        assertEq(read2, fund2Value);
        assertEq(readCap, cap);

        if (amount == 0) {
            vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAmount.selector);
            cruise.topUpFund2(0, "fuzz");
            return;
        }
        if (amount > cap) {
            vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, cap, amount));
            cruise.topUpFund2(amount, "fuzz");
            assertEq(cruise.value(), fund1Value);
            assertEq(degen.value(), fund2Value);
            return;
        }

        uint256 sum = cruise.value() + degen.value();
        cruise.topUpFund2(amount, "fuzz");
        assertEq(cruise.value(), fund1Value - amount);
        assertEq(degen.value(), fund2Value + amount);
        assertEq(cruise.value() + degen.value(), sum);
        assertEq(usdc.allowance(address(cruise), address(degen)), 0);
    }

    function testFuzz_TopUpCapAndOneAbove(uint256 share1, uint256 share2, uint256 fund1Value, uint256 fund2Value)
        public
    {
        (share1, share2) = _shares(share1, share2);
        fund1Value = bound(fund1Value, 0, MAX_SHARE);
        fund2Value = bound(fund2Value, 0, MAX_SHARE);
        uint256 cap = _move(share1, fund1Value, share2, fund2Value);

        (CruiseControl cruise, DegenDriver degen) = _pair(share1, share2);
        _supply(cruise, fund1Value);
        _supply(degen, fund2Value);
        cruise.setFund2(degen);

        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__TopUpAboveCap.selector, cap, cap + 1));
        cruise.topUpFund2(cap + 1, "over");
        if (cap == 0) {
            assertEq(cruise.value(), fund1Value);
            return;
        }

        cruise.topUpFund2(cap, "exact");
        assertEq(cruise.value(), fund1Value - cap);
        assertEq(degen.value(), fund2Value + cap);
        assertEq(cruise.value() + degen.value(), fund1Value + fund2Value);
        (,, uint256 next) = cruise.topUpCap();
        assertEq(next, _move(share1, fund1Value - cap, share2, fund2Value + cap));
    }

    function testFuzz_IdleThenFarm(uint256 idle, uint256 extra, uint256 amount) public {
        idle = bound(idle, 1, 1_000_000 * 10 ** 6);
        extra = bound(extra, 4, 1_000_000 * 10 ** 6);
        uint256 principal = 3 * idle + extra;
        uint256 cap = _move(3, idle + principal, 1, 0);
        amount = bound(amount, idle + 1, cap);

        (CruiseControl cruise, DegenDriver degen, MockFarm farm) = _fundedPair(3, 1);
        cruise.setStrategy(farm);
        _supply(cruise, idle + principal);
        cruise.deposit(principal);
        cruise.setFund2(degen);
        assertEq(cruise.idle(), idle);
        assertEq(cruise.principal(), principal);
        assertGt(cap, idle);

        cruise.topUpFund2(amount, "mixed");

        assertEq(cruise.idle(), 0);
        assertEq(cruise.principal(), principal - (amount - idle));
        assertEq(degen.idle(), amount);
        assertEq(degen.principal(), 0);
        assertEq(cruise.value() + degen.value(), idle + principal);
        assertEq(usdc.allowance(address(cruise), address(degen)), 0);
    }

    function _shares(uint256 share1, uint256 share2) private pure returns (uint256 bounded1, uint256 bounded2) {
        bounded1 = bound(share1, 2, MAX_SHARE);
        bounded2 = bound(share2, 1, bounded1 - 1);
    }

    function _move(uint256 payerShare, uint256 payerValue, uint256 receiverShare, uint256 receiverValue)
        private
        pure
        returns (uint256 amount)
    {
        uint256 owed = receiverShare * payerValue;
        uint256 held = payerShare * receiverValue;
        if (owed <= held) {
            return 0;
        }
        amount = (owed - held) / (payerShare + receiverShare);
    }

    function _pair(uint256 share1, uint256 share2) private returns (CruiseControl cruise, DegenDriver degen) {
        (cruise, degen,) = _fundedPair(share1, share2);
    }

    function _fundedPair(uint256 share1, uint256 share2)
        private
        returns (CruiseControl cruise, DegenDriver degen, MockFarm farm)
    {
        farm = new MockFarm(usdc, clock, 1, address(this));
        IMockFarm[] memory farms = new IMockFarm[](1);
        farms[0] = farm;
        cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, share1, share2, farms, address(this));
        degen = new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, share1, share2, farms, address(this));
        farm.addDepositor(address(cruise));
        farm.addDepositor(address(degen));
    }

    function _supply(TreasuryFund fund, uint256 amount) private {
        if (amount == 0) {
            return;
        }
        usdc.approve(address(fund), amount);
        fund.supply(amount);
    }

    function _farms() private returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = new MockFarm(usdc, clock, 1, address(this));
    }
}
