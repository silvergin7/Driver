// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {ITreasuryFund} from "../../src/interfaces/ITreasuryFund.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";

contract HarvestFuzzTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant SEED_DVR = 1_000 * 10 ** 18;
    uint256 internal constant SEED_USDC = 10_000 * 10 ** 6;

    function testFuzz_EpochBounds(uint256 epoch) public {
        epoch = bound(epoch, 0, 120 days);
        DemoDriverClock clock = new DemoDriverClock(address(this));
        if (epoch < 1 days || epoch > 90 days) {
            vm.expectRevert(
                abi.encodeWithSelector(RoundSchedule.RoundSchedule__EpochOutOfRange.selector, epoch, 1 days, 90 days)
            );
            new RoundSchedule(clock, epoch);
            return;
        }
        RoundSchedule schedule = new RoundSchedule(clock, epoch);
        assertEq(schedule.i_epoch(), epoch);
    }

    function testFuzz_HarvestSplitAndBurnMatchTheFormula(uint256 principal, uint256 elapsed, uint256 apr) public {
        principal = bound(principal, 1, 1_000_000 * 10 ** 6);
        elapsed = bound(elapsed, 1 days, 90 days);
        apr = bound(apr, 1, 20_000);

        MockUSDC usdc = new MockUSDC(address(this));
        DriverToken token = new DriverToken(address(this));
        DemoDriverClock clock = new DemoDriverClock(address(this));
        TaxSplitter splitter = new TaxSplitter(usdc, address(this));
        OfficialPool pool = new OfficialPool(token, usdc, splitter, address(this), 100);
        splitter.setPool(address(pool));
        token.mint(address(this), SEED_DVR);
        usdc.mint(address(this), SEED_USDC + principal + 1_000_000 * 10 ** 6);
        token.approve(address(pool), SEED_DVR);
        usdc.approve(address(pool), SEED_USDC);
        pool.addLiquidity(SEED_DVR, SEED_USDC);

        MockFarm farm = new MockFarm(usdc, clock, apr, address(this));
        RoundSchedule schedule = new RoundSchedule(clock, elapsed);
        IMockFarm[] memory farms = new IMockFarm[](1);
        farms[0] = farm;
        CruiseControl fund =
            new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, farms, address(this));
        farm.addDepositor(address(fund));
        usdc.approve(address(farm), 1_000_000 * 10 ** 6);
        farm.fundRewards(1_000_000 * 10 ** 6);
        usdc.approve(address(fund), principal);
        fund.supply(principal);
        fund.setStrategy(farm);
        fund.deposit(principal);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(fund));
        clock.advanceTime(elapsed);

        uint256 rewards = Math.mulDiv(principal, apr * elapsed, BPS * YEAR);
        uint256 reserveDvr = SEED_DVR;
        uint256 reserveUsdc = SEED_USDC;
        fund.harvest(0);

        ITreasuryFund.Harvest memory harvest_ = fund.lastHarvest();
        assertEq(harvest_.rewards, rewards);
        assertEq(harvest_.compounded + rewards / 2, rewards);
        assertEq(harvest_.compounded, rewards - rewards / 2);
        uint256 half = rewards / 2;
        if (half == 0) {
            assertEq(harvest_.buybackSpent, 0);
            assertEq(harvest_.dvrBurned, 0);
            assertEq(fund.pendingBuyback(), 0);
            return;
        }
        (uint256 dvrOut, bool deferred) = _quoteBuy(reserveDvr, reserveUsdc, half);
        if (deferred) {
            assertEq(harvest_.buybackSpent, 0);
            assertEq(harvest_.dvrBurned, 0);
            assertEq(fund.pendingBuyback(), half);
            return;
        }
        assertEq(harvest_.buybackSpent, half);
        assertEq(harvest_.dvrBurned, dvrOut);
        assertEq(fund.dvrBoughtBack(), dvrOut);
        assertEq(fund.pendingBuyback(), 0);
    }

    function _quoteBuy(uint256 reserveDvr, uint256 reserveUsdc, uint256 amountIn)
        private
        pure
        returns (uint256 dvrOut, bool deferred)
    {
        uint256 usdcTax = Math.mulDiv(amountIn, 100, BPS, Math.Rounding.Ceil);
        uint256 toCurve = amountIn - usdcTax;
        if (toCurve == 0) {
            return (0, true);
        }
        dvrOut = Math.mulDiv(reserveDvr, toCurve, reserveUsdc + toCurve);
        if (dvrOut == 0) {
            return (0, true);
        }
        deferred = false;
    }
}
