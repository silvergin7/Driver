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

contract EmergencyWithdrawFuzzTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;
    uint256 internal constant MAX_AMOUNT = 1e15;

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
        usdc.mint(address(this), type(uint128).max);
    }

    function testFuzz_ExitMovesPrincipalIntoIdle(uint256 supplied, uint256 deposited, uint256 other) public {
        supplied = bound(supplied, 1, MAX_AMOUNT);
        deposited = bound(deposited, 1, supplied);
        other = bound(other, 0, MAX_AMOUNT);
        (CruiseControl cruise, DegenDriver degen, MockFarm farm) = _scene();
        _supply(cruise, supplied);
        cruise.setStrategy(farm);
        cruise.deposit(deposited);
        _supply(degen, other);
        uint256 idleBefore = cruise.idle();
        uint256 sum = cruise.value() + degen.value();

        cruise.emergencyWithdraw("risk");

        assertEq(cruise.idle(), idleBefore + deposited);
        assertEq(cruise.principal(), 0);
        assertEq(cruise.value() + degen.value(), sum);
        assertEq(address(cruise.activeFarm()), address(0));
        assertTrue(farm.paused());
        assertFalse(cruise.isStrategy(address(farm)));

        vm.expectRevert(TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        cruise.emergencyWithdraw("again");
    }

    function testFuzz_Reason(uint256 deposited, string memory reason) public {
        deposited = bound(deposited, 1, MAX_AMOUNT);
        vm.assume(bytes(reason).length <= 64);
        (CruiseControl cruise,, MockFarm farm) = _scene();
        _supply(cruise, deposited);
        cruise.setStrategy(farm);
        cruise.deposit(deposited);

        if (bytes(reason).length == 0) {
            vm.expectRevert(TreasuryFund.TreasuryFund__EmptyReason.selector);
            cruise.emergencyWithdraw(reason);
            assertEq(cruise.principal(), deposited);
            assertEq(cruise.idle(), 0);
            assertFalse(farm.paused());
            (address untouched,,) = cruise.lastEmergencyExit();
            assertEq(untouched, address(0));
            return;
        }

        cruise.emergencyWithdraw(reason);

        (address strategy, uint256 amount, string memory stored) = cruise.lastEmergencyExit();
        assertEq(strategy, address(farm));
        assertEq(amount, deposited);
        assertEq(stored, reason);
        assertEq(cruise.idle(), deposited);
        assertEq(cruise.principal(), 0);
    }

    function _scene() private returns (CruiseControl cruise, DegenDriver degen, MockFarm farm) {
        farm = new MockFarm(usdc, clock, 500, address(this));
        MockFarm degenFarm = new MockFarm(usdc, clock, 4_000, address(this));
        cruise = new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, _one(farm), address(this));
        degen = new DegenDriver(
            usdc, clock, schedule, splitter, pool, cruise, SHARE_1, SHARE_2, _one(degenFarm), address(this)
        );
        farm.addDepositor(address(cruise));
        degenFarm.addDepositor(address(degen));
        cruise.setFund2(degen);
    }

    function _supply(TreasuryFund fund, uint256 amount) private {
        if (amount == 0) {
            return;
        }
        usdc.approve(address(fund), amount);
        fund.supply(amount);
    }

    function _one(IMockFarm farm) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm;
    }
}
