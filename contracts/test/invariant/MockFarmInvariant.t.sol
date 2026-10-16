// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {MockFarmHandler} from "./handlers/MockFarmHandler.sol";

contract MockFarmInvariantTest is Test {
    uint256 internal constant ACTORS = 3;
    uint256 internal constant APR_BPS = 500;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    MockFarm internal farm;
    MockFarmHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        usdc = new MockUSDC(owner);
        clock = new DemoDriverClock(owner);
        farm = new MockFarm(usdc, clock, APR_BPS, owner);

        address[] memory actors = new address[](ACTORS);
        actors[0] = makeAddr("actor0");
        actors[1] = makeAddr("actor1");
        actors[2] = makeAddr("actor2");

        vm.startPrank(owner);
        usdc.approve(address(farm), type(uint256).max);
        for (uint256 i = 0; i < ACTORS; i++) {
            farm.addDepositor(actors[i]);
        }
        vm.stopPrank();
        for (uint256 i = 0; i < ACTORS; i++) {
            vm.prank(actors[i]);
            usdc.approve(address(farm), type(uint256).max);
        }

        handler = new MockFarmHandler(usdc, clock, farm, owner, APR_BPS, actors);

        excludeContract(address(usdc));
        excludeContract(address(clock));
        excludeContract(address(farm));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.claim.selector;
        selectors[3] = handler.capClaim.selector;
        selectors[4] = handler.emergencyWithdraw.selector;
        selectors[5] = handler.fundRewards.selector;
        selectors[6] = handler.donate.selector;
        selectors[7] = handler.warpForward.selector;
        selectors[8] = handler.advanceTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_PrincipalMatchesGhost() public view {
        uint256 sum;
        uint256 count = handler.actorCount();
        for (uint256 i = 0; i < count; i++) {
            address account = handler.actor(i);
            uint256 ghost = handler.s_ghostPrincipal(account);
            assertEq(farm.principalOf(account), ghost);
            sum += ghost;
        }
        assertEq(farm.totalPrincipal(), handler.s_ghostTotalPrincipal());
        assertEq(sum, handler.s_ghostTotalPrincipal());
    }

    function invariant_ReserveMatchesGhost() public view {
        assertEq(farm.rewardReserve(), handler.s_ghostReserve());
    }

    function invariant_BalanceCoversLedgers() public view {
        assertEq(
            usdc.balanceOf(address(farm)),
            handler.s_ghostTotalPrincipal() + handler.s_ghostReserve() + handler.s_ghostDonated()
        );
    }

    function invariant_PaidNeverExceedsEarned() public view {
        uint256 count = handler.actorCount();
        for (uint256 i = 0; i < count; i++) {
            address account = handler.actor(i);
            assertLe(handler.s_ghostPaid(account) + farm.accrued(account), handler.ghostEarnedOf(account));
            assertEq(farm.accrued(account), handler.ghostOwedOf(account));
        }
    }

    function afterInvariant() public view {
        assertGt(handler.s_ghostDeposits(), 0);
        assertGt(handler.s_ghostWithdrawals(), 0);
        assertGt(handler.s_ghostClaims(), 0);
        assertGt(handler.s_ghostCapClaims(), 0);
        assertGt(handler.s_ghostEmergencyWithdrawals(), 0);
        assertGt(handler.s_ghostFunds(), 0);
        assertGt(handler.s_ghostDonations(), 0);
        assertGt(handler.s_ghostWarps(), 0);
        assertGt(handler.s_ghostAdvances(), 0);
    }
}
