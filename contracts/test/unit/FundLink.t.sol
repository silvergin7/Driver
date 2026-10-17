// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";
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

contract FundLinkTest is Test {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    TaxSplitter internal splitter;
    OfficialPool internal pool;
    RoundSchedule internal schedule;
    MockFarm internal farm;
    CruiseControl internal cruise;
    DegenDriver internal degen;
    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC(owner);
        clock = new DemoDriverClock(owner);
        DriverToken token = new DriverToken(owner);
        splitter = new TaxSplitter(usdc, owner);
        pool = new OfficialPool(token, usdc, splitter, owner, 100);
        schedule = new RoundSchedule(clock, 30 days);
        vm.prank(owner);
        splitter.setPool(address(pool));
        farm = new MockFarm(usdc, clock, 500, owner);
        cruise = _cruise(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, farm);
        degen = _degen(usdc, clock, schedule, splitter, pool, cruise, SHARE_1, SHARE_2, farm);
    }

    function test_SetFund2StoresTheBackPointer() public {
        assertEq(address(cruise.fund2()), address(0));

        vm.expectEmit(true, false, false, true, address(cruise));
        emit CruiseControl.Fund2Set(address(degen));
        vm.prank(owner);
        cruise.setFund2(degen);

        assertEq(address(cruise.fund2()), address(degen));
        assertEq(address(degen.i_fund1()), address(cruise));
    }

    function test_RevertWhen_Fund2IsSetTwice() public {
        vm.startPrank(owner);
        cruise.setFund2(degen);
        vm.expectRevert(CruiseControl.CruiseControl__Fund2AlreadySet.selector);
        cruise.setFund2(degen);
        vm.stopPrank();
    }

    function test_RevertWhen_Fund2IsZero() public {
        vm.expectRevert(TreasuryFund.TreasuryFund__ZeroAddress.selector);
        vm.prank(owner);
        cruise.setFund2(DegenDriver(address(0)));
    }

    function test_RevertWhen_SetFund2CallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        cruise.setFund2(degen);
    }

    function test_RevertWhen_Fund1ConstructorArgumentIsZero() public {
        vm.expectRevert(DegenDriver.DegenDriver__ZeroAddress.selector);
        new DegenDriver(
            usdc, clock, schedule, splitter, pool, CruiseControl(address(0)), SHARE_1, SHARE_2, _one(farm), owner
        );
    }

    function test_RevertWhen_Fund2PointsAtAnotherFund() public {
        CruiseControl other = _cruise(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, farm);
        DegenDriver pointed = _degen(usdc, clock, schedule, splitter, pool, other, SHARE_1, SHARE_2, farm);

        vm.expectRevert(abi.encodeWithSelector(CruiseControl.CruiseControl__Fund2Mismatch.selector, address(pointed)));
        vm.prank(owner);
        cruise.setFund2(pointed);
    }

    function test_RevertWhen_Fund2TokenMismatches() public {
        MockUSDC otherUsdc = new MockUSDC(owner);
        DriverToken token = new DriverToken(owner);
        TaxSplitter otherSplitter = new TaxSplitter(otherUsdc, owner);
        OfficialPool otherPool = new OfficialPool(token, otherUsdc, otherSplitter, owner, 100);
        vm.prank(owner);
        otherSplitter.setPool(address(otherPool));
        MockFarm otherFarm = new MockFarm(otherUsdc, clock, 500, owner);
        DegenDriver mismatched =
            _degen(otherUsdc, clock, schedule, otherSplitter, otherPool, cruise, SHARE_1, SHARE_2, otherFarm);

        vm.expectRevert(
            abi.encodeWithSelector(CruiseControl.CruiseControl__Fund2Mismatch.selector, address(mismatched))
        );
        vm.prank(owner);
        cruise.setFund2(mismatched);
    }

    function test_RevertWhen_Fund2ClockMismatches() public {
        DemoDriverClock otherClock = new DemoDriverClock(owner);
        RoundSchedule otherSchedule = new RoundSchedule(otherClock, 30 days);
        MockFarm otherFarm = new MockFarm(usdc, otherClock, 500, owner);
        DegenDriver mismatched =
            _degen(usdc, otherClock, otherSchedule, splitter, pool, cruise, SHARE_1, SHARE_2, otherFarm);

        vm.expectRevert(
            abi.encodeWithSelector(CruiseControl.CruiseControl__Fund2Mismatch.selector, address(mismatched))
        );
        vm.prank(owner);
        cruise.setFund2(mismatched);
    }

    function test_RevertWhen_Fund2ScheduleMismatches() public {
        RoundSchedule otherSchedule = new RoundSchedule(clock, 30 days);
        DegenDriver mismatched = _degen(usdc, clock, otherSchedule, splitter, pool, cruise, SHARE_1, SHARE_2, farm);

        vm.expectRevert(
            abi.encodeWithSelector(CruiseControl.CruiseControl__Fund2Mismatch.selector, address(mismatched))
        );
        vm.prank(owner);
        cruise.setFund2(mismatched);
    }

    function test_RevertWhen_Fund1ShareMismatches() public {
        DegenDriver mismatched = _degen(usdc, clock, schedule, splitter, pool, cruise, 30_000 * 10 ** 6, SHARE_2, farm);

        vm.expectRevert(
            abi.encodeWithSelector(CruiseControl.CruiseControl__Fund2Mismatch.selector, address(mismatched))
        );
        vm.prank(owner);
        cruise.setFund2(mismatched);
    }

    function test_RevertWhen_Fund2ShareMismatches() public {
        DegenDriver mismatched = _degen(usdc, clock, schedule, splitter, pool, cruise, SHARE_1, 1, farm);

        vm.expectRevert(
            abi.encodeWithSelector(CruiseControl.CruiseControl__Fund2Mismatch.selector, address(mismatched))
        );
        vm.prank(owner);
        cruise.setFund2(mismatched);
    }

    function _cruise(
        MockUSDC usdc_,
        IDriverClock clock_,
        RoundSchedule schedule_,
        TaxSplitter splitter_,
        IOfficialPool pool_,
        uint256 share1,
        uint256 share2,
        MockFarm farm_
    ) private returns (CruiseControl cruise_) {
        cruise_ = new CruiseControl(usdc_, clock_, schedule_, splitter_, pool_, share1, share2, _one(farm_), owner);
    }

    function _degen(
        MockUSDC usdc_,
        IDriverClock clock_,
        RoundSchedule schedule_,
        TaxSplitter splitter_,
        IOfficialPool pool_,
        CruiseControl fund1,
        uint256 share1,
        uint256 share2,
        MockFarm farm_
    ) private returns (DegenDriver degen_) {
        degen_ = new DegenDriver(usdc_, clock_, schedule_, splitter_, pool_, fund1, share1, share2, _one(farm_), owner);
    }

    function _one(IMockFarm farm_) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = farm_;
    }
}
