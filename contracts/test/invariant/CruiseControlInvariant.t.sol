// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {CruiseControlHandler} from "./handlers/CruiseControlHandler.sol";

contract CruiseControlInvariantTest is Test {
    uint256 internal constant APR_A = 500;
    uint256 internal constant APR_B = 4_000;
    uint256 internal constant RESERVE = 1_000_000 * 10 ** 6;
    uint256 internal constant STRANGER_MINT = 100 * 10 ** 6;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    MockFarm internal farmA;
    MockFarm internal farmB;
    CruiseControl internal fund;
    CruiseControlHandler internal handler;
    address internal owner = makeAddr("owner");
    address internal farmOwner = makeAddr("farmOwner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC(owner);
        clock = new DemoDriverClock(owner);
        DriverToken token = new DriverToken(owner);
        TaxSplitter splitter = new TaxSplitter(usdc, owner);
        OfficialPool pool = new OfficialPool(token, usdc, splitter, owner, 100);
        RoundSchedule schedule = new RoundSchedule(clock, 30 days);
        vm.prank(owner);
        splitter.setPool(address(pool));
        farmA = new MockFarm(usdc, clock, APR_A, farmOwner);
        farmB = new MockFarm(usdc, clock, APR_B, farmOwner);
        fund = new CruiseControl(usdc, clock, schedule, splitter, pool, _pair(), owner);

        vm.startPrank(farmOwner);
        farmA.addDepositor(address(fund));
        farmB.addDepositor(address(fund));
        vm.stopPrank();
        vm.prank(owner);
        usdc.approve(address(fund), type(uint256).max);

        handler = new CruiseControlHandler(
            usdc, clock, fund, farmA, farmB, owner, farmOwner, stranger, RESERVE, STRANGER_MINT
        );

        excludeContract(address(usdc));
        excludeContract(address(clock));
        excludeContract(address(token));
        excludeContract(address(splitter));
        excludeContract(address(pool));
        excludeContract(address(farmA));
        excludeContract(address(farmB));
        excludeContract(address(fund));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.supply.selector;
        selectors[1] = handler.deposit.selector;
        selectors[2] = handler.switchFarm.selector;
        selectors[3] = handler.fundReserve.selector;
        selectors[4] = handler.paidSwitch.selector;
        selectors[5] = handler.cappedSwitch.selector;
        selectors[6] = handler.donate.selector;
        selectors[7] = handler.warpForward.selector;
        selectors[8] = handler.advanceTime.selector;
        selectors[9] = handler.unauthorizedSupply.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_IdleMatchesGhost() public view {
        assertEq(fund.idle(), handler.s_ghostIdle());
    }

    function invariant_HeldRewardsMatchGhost() public view {
        assertEq(fund.heldRewards(), handler.s_ghostHeldRewards());
    }

    function invariant_PrincipalMatchesGhost() public view {
        assertEq(fund.principal(), handler.s_ghostPrincipal());
    }

    function invariant_ValueMatchesIdlePlusPrincipal() public view {
        assertEq(fund.value(), handler.s_ghostIdle() + handler.s_ghostPrincipal());
    }

    function invariant_FundBalanceMatchesGhosts() public view {
        assertEq(
            usdc.balanceOf(address(fund)),
            handler.s_ghostIdle() + handler.s_ghostHeldRewards() + handler.s_ghostDonated()
        );
    }

    function invariant_FarmPrincipalsMatchGhost() public view {
        uint256 ghost = handler.s_ghostPrincipal();
        address active = address(fund.activeFarm());
        if (active == address(0)) {
            assertEq(ghost, 0);
            assertEq(farmA.principalOf(address(fund)), 0);
            assertEq(farmB.principalOf(address(fund)), 0);
        } else if (active == address(farmA)) {
            assertEq(farmA.principalOf(address(fund)), ghost);
            assertEq(farmB.principalOf(address(fund)), 0);
        } else {
            assertEq(active, address(farmB));
            assertEq(farmB.principalOf(address(fund)), ghost);
            assertEq(farmA.principalOf(address(fund)), 0);
        }
    }

    function invariant_PendingRewardsMatchGhost() public view {
        assertEq(fund.pendingRewards(), handler.ghostPendingRewards());
    }

    function invariant_OwnerBalanceMatchesGhost() public view {
        assertEq(usdc.balanceOf(owner), handler.s_mintedToOwner() - handler.s_suppliedByOwner());
    }

    function invariant_StrangerBalanceMatchesGhost() public view {
        assertEq(usdc.balanceOf(stranger), handler.s_mintedToStranger() - handler.s_suppliedByStranger());
    }

    function afterInvariant() public view {
        assertGt(handler.s_ghostSupplies(), 0);
        assertGt(handler.s_ghostDeposits(), 0);
        assertGt(handler.s_ghostSwitches(), 0);
        assertGt(handler.s_ghostFundReserves(), 0);
        assertGt(handler.s_ghostPaidSwitches(), 0);
        assertGt(handler.s_ghostCappedSwitches(), 0);
        assertGt(handler.s_ghostDonations(), 0);
        assertGt(handler.s_ghostWarps(), 0);
        assertGt(handler.s_ghostAdvances(), 0);
        assertGt(handler.s_ghostUnauthorized(), 0);
    }

    function _pair() private view returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](2);
        farms[0] = farmA;
        farms[1] = farmB;
    }
}
