// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DegenDriver} from "../../src/DegenDriver.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {TreasuryFund} from "../../src/TreasuryFund.sol";

contract DegenDriverTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;

    MockUSDC internal usdc;
    MockFarm internal highway;
    MockFarm internal autobahn;
    MockFarm internal drift;
    RoundSchedule internal schedule;
    DegenDriver internal fund;
    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC(owner);
        DemoDriverClock clock = new DemoDriverClock(owner);
        DriverToken token = new DriverToken(owner);
        TaxSplitter splitter = new TaxSplitter(usdc, owner);
        OfficialPool pool = new OfficialPool(token, usdc, splitter, owner, 100);
        schedule = new RoundSchedule(clock, 30 days);
        vm.prank(owner);
        splitter.setPool(address(pool));
        highway = new MockFarm(usdc, clock, 4_000, owner);
        autobahn = new MockFarm(usdc, clock, 8_000, owner);
        drift = new MockFarm(usdc, clock, 16_000, owner);

        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = highway;
        farms[1] = autobahn;
        farms[2] = drift;
        fund = new DegenDriver(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, farms, owner);
    }

    function test_ConstructorListsTheThreeFarms() public view {
        assertEq(uint256(fund.i_fundId()), uint256(TaxSplitter.FundId.Fund2));
        assertEq(address(fund.i_schedule()), address(schedule));
        assertEq(fund.strategyCount(), 3);
        assertEq(address(fund.strategyAt(0)), address(highway));
        assertEq(address(fund.strategyAt(1)), address(autobahn));
        assertEq(address(fund.strategyAt(2)), address(drift));
        assertTrue(fund.isStrategy(address(highway)));
        assertTrue(fund.isStrategy(address(autobahn)));
        assertTrue(fund.isStrategy(address(drift)));
        assertEq(address(fund.activeFarm()), address(0));
        assertEq(fund.idle(), 0);
        assertEq(fund.value(), 0);
        assertEq(fund.i_fund1Usdc(), SHARE_1);
        assertEq(fund.i_fund2Usdc(), SHARE_2);
    }

    function test_RevertWhen_DepositHasNoActiveFarm() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__NoActiveFarm.selector);
        vm.prank(owner);
        fund.deposit(1);
    }

    function test_RevertWhen_SupplyCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        fund.supply(1);
    }

    function test_HasNoExternalSetStrategy() public {
        (bool ok, bytes memory data) =
            address(fund).call(abi.encodeWithSignature("setStrategy(address)", address(highway)));
        assertFalse(ok);
        assertEq(data.length, 0);
    }
}
