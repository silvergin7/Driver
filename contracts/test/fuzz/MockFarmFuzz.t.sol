// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";

contract MockFarmFuzzTest is Test {
    uint256 internal constant MIN_PRINCIPAL = 1;
    uint256 internal constant MAX_PRINCIPAL = 1e15;
    uint256 internal constant MAX_ELAPSED = 3_650 days;
    uint256 internal constant MIN_APR_BPS = 1;
    uint256 internal constant MAX_APR_BPS = 16_000;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    MockUSDC internal usdc;
    DemoDriverClock internal clock;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        usdc = new MockUSDC(owner);
        clock = new DemoDriverClock(owner);
    }

    function testFuzz_AccruedMatchesMulDiv(uint256 principal, uint256 elapsed, uint256 aprBps) public {
        principal = bound(principal, MIN_PRINCIPAL, MAX_PRINCIPAL);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        aprBps = bound(aprBps, MIN_APR_BPS, MAX_APR_BPS);
        MockFarm farm = _deploy(aprBps);
        _deposit(farm, principal);

        vm.warp(block.timestamp + elapsed);

        assertEq(farm.accrued(alice), Math.mulDiv(principal, aprBps * elapsed, BPS_DENOMINATOR * SECONDS_PER_YEAR));
    }

    function testFuzz_ClaimPaysAtMostTheReserve(uint256 principal, uint256 elapsed, uint256 aprBps, uint256 reserve)
        public
    {
        principal = bound(principal, MIN_PRINCIPAL, MAX_PRINCIPAL);
        elapsed = bound(elapsed, 0, MAX_ELAPSED);
        aprBps = bound(aprBps, MIN_APR_BPS, MAX_APR_BPS);
        reserve = bound(reserve, 0, MAX_PRINCIPAL);
        MockFarm farm = _deploy(aprBps);
        _deposit(farm, principal);
        if (reserve != 0) {
            _fund(farm, reserve);
        }

        vm.warp(block.timestamp + elapsed);
        uint256 expected = Math.mulDiv(principal, aprBps * elapsed, BPS_DENOMINATOR * SECONDS_PER_YEAR);
        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 paid = farm.claim();

        assertEq(usdc.balanceOf(alice) - before, paid);
        assertEq(paid, expected < reserve ? expected : reserve);
    }

    function testFuzz_WithdrawPaysAtMostPrincipal(uint256 principal, uint256 amount) public {
        principal = bound(principal, MIN_PRINCIPAL, MAX_PRINCIPAL);
        amount = bound(amount, MIN_PRINCIPAL, principal);
        MockFarm farm = _deploy(MIN_APR_BPS);
        _deposit(farm, principal);

        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        farm.withdraw(amount);

        assertEq(usdc.balanceOf(alice) - before, amount);
        assertEq(farm.principalOf(alice), principal - amount);
    }

    function _deploy(uint256 aprBps) internal returns (MockFarm farm) {
        farm = new MockFarm(usdc, clock, aprBps, owner);
        vm.prank(owner);
        farm.addDepositor(alice);
        vm.prank(alice);
        usdc.approve(address(farm), type(uint256).max);
    }

    function _deposit(MockFarm farm, uint256 amount) internal {
        vm.prank(owner);
        usdc.mint(alice, amount);
        vm.prank(alice);
        farm.deposit(amount);
    }

    function _fund(MockFarm farm, uint256 amount) internal {
        vm.startPrank(owner);
        usdc.mint(owner, amount);
        usdc.approve(address(farm), amount);
        farm.fundRewards(amount);
        vm.stopPrank();
    }
}
