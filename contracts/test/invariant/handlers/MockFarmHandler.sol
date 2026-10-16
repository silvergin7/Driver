// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DemoDriverClock} from "../../../src/DemoDriverClock.sol";
import {MockFarm} from "../../../src/MockFarm.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";

contract MockFarmHandler is Test {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant MAX_AMOUNT = 1e15;
    uint256 internal constant MAX_WARP = 365 days;

    MockUSDC internal immutable i_usdc;
    DemoDriverClock internal immutable i_clock;
    MockFarm internal immutable i_farm;
    address internal immutable i_owner;
    uint256 internal immutable i_aprBps;

    address[] internal s_actors;
    mapping(address account => uint256 amount) public s_ghostPrincipal;
    mapping(address account => uint256 amount) public s_ghostPaid;
    mapping(address account => uint256 amount) public s_ghostEarned;
    mapping(address account => uint256 amount) public s_ghostOwed;
    mapping(address account => uint256 timestamp) internal s_ghostLast;
    uint256 public s_ghostTotalPrincipal;
    uint256 public s_ghostReserve;
    uint256 public s_ghostDonated;

    uint256 public s_ghostDeposits;
    uint256 public s_ghostWithdrawals;
    uint256 public s_ghostClaims;
    uint256 public s_ghostCapClaims;
    uint256 public s_ghostEmergencyWithdrawals;
    uint256 public s_ghostFunds;
    uint256 public s_ghostDonations;
    uint256 public s_ghostWarps;
    uint256 public s_ghostAdvances;

    constructor(
        MockUSDC usdc,
        DemoDriverClock clock,
        MockFarm farm,
        address owner_,
        uint256 aprBps,
        address[] memory actors_
    ) {
        i_usdc = usdc;
        i_clock = clock;
        i_farm = farm;
        i_owner = owner_;
        i_aprBps = aprBps;
        uint256 length = actors_.length;
        for (uint256 i = 0; i < length; i++) {
            s_actors.push(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256 count) {
        count = s_actors.length;
    }

    function actor(uint256 index) external view returns (address account) {
        account = s_actors[index];
    }

    function ghostEarnedOf(address account) external view returns (uint256 earned) {
        earned = s_ghostEarned[account] + _pending(account);
    }

    function ghostOwedOf(address account) external view returns (uint256 owed) {
        owed = s_ghostOwed[account] + _pending(account);
    }

    function deposit(uint256 actorIndex, uint256 amount) external {
        address account = _account(actorIndex);
        amount = bound(amount, 1, MAX_AMOUNT);
        _deposit(account, amount);
        s_ghostDeposits += 1;
    }

    function withdraw(uint256 actorIndex, uint256 amount) external {
        address account = _account(actorIndex);
        uint256 principal = s_ghostPrincipal[account];
        if (principal == 0) return;

        amount = bound(amount, 1, principal);
        _checkpoint(account);
        vm.prank(account);
        i_farm.withdraw(amount);

        s_ghostPrincipal[account] = principal - amount;
        s_ghostTotalPrincipal -= amount;
        s_ghostWithdrawals += 1;
    }

    function claim(uint256 actorIndex) external {
        address account = _account(actorIndex);
        _checkpoint(account);
        _claim(account);
        s_ghostClaims += 1;
    }

    function capClaim(uint256 actorIndex) external {
        address account = _account(actorIndex);
        _openRewardsPastReserve(account);

        uint256 owed = s_ghostOwed[account] + _pending(account);
        if (owed < 2 || s_ghostReserve >= owed) return;

        _checkpoint(account);
        uint256 low = s_ghostReserve == 0 ? 1 : s_ghostReserve;
        uint256 target = bound(actorIndex, low, owed - 1);
        if (s_ghostReserve < target) {
            _fund(target - s_ghostReserve);
        }

        uint256 reserveBefore = s_ghostReserve;
        uint256 received = _claim(account);
        assertEq(received, reserveBefore);
        assertEq(i_farm.accrued(account), owed - received);
        s_ghostCapClaims += 1;
    }

    function emergencyWithdraw(uint256 actorIndex) external {
        address account = _account(actorIndex);
        uint256 principal = s_ghostPrincipal[account];
        if (principal == 0) return;

        _checkpoint(account);
        s_ghostOwed[account] = 0;
        vm.prank(account);
        i_farm.emergencyWithdraw();

        s_ghostPrincipal[account] = 0;
        s_ghostTotalPrincipal -= principal;
        s_ghostEmergencyWithdrawals += 1;
    }

    function fundRewards(uint256 amount) external {
        amount = bound(amount, 1, MAX_AMOUNT);
        _fund(amount);
        s_ghostFunds += 1;
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1, MAX_AMOUNT);
        vm.prank(i_owner);
        i_usdc.mint(address(this), amount);
        assertTrue(i_usdc.transfer(address(i_farm), amount));

        s_ghostDonated += amount;
        s_ghostDonations += 1;
    }

    function warpForward(uint256 secondsForward) external {
        secondsForward = bound(secondsForward, 1, MAX_WARP);
        _warp(secondsForward);
        s_ghostWarps += 1;
    }

    function advanceTime(uint256 secondsForward) external {
        secondsForward = bound(secondsForward, 1, i_clock.MAX_ADVANCE());
        vm.prank(i_owner);
        i_clock.advanceTime(secondsForward);
        s_ghostAdvances += 1;
    }

    function _openRewardsPastReserve(address account) private {
        uint256 owed = s_ghostOwed[account] + _pending(account);
        if (owed >= 2 && s_ghostReserve < owed) return;

        if (s_ghostPrincipal[account] == 0) {
            _deposit(account, MAX_AMOUNT);
        }
        owed = s_ghostOwed[account] + _pending(account);
        if (owed >= 2 && s_ghostReserve < owed) return;

        if (s_ghostPrincipal[account] < MAX_AMOUNT) {
            _deposit(account, MAX_AMOUNT);
        }

        uint256 stored = s_ghostOwed[account];
        uint256 needed = s_ghostReserve + 2;
        if (stored >= needed) return;

        uint256 principal = s_ghostPrincipal[account];
        uint256 target = needed - stored;
        uint256 denominator = BPS_DENOMINATOR * SECONDS_PER_YEAR;
        uint256 step = (target * denominator + principal * i_aprBps - 1) / (principal * i_aprBps);
        if (step == 0) step = 1;
        _warp(step);
    }

    function _deposit(address account, uint256 amount) private {
        _checkpoint(account);
        vm.prank(i_owner);
        i_usdc.mint(account, amount);
        vm.prank(account);
        i_farm.deposit(amount);
        s_ghostPrincipal[account] += amount;
        s_ghostTotalPrincipal += amount;
    }

    function _fund(uint256 amount) private {
        vm.prank(i_owner);
        i_usdc.mint(i_owner, amount);
        vm.prank(i_owner);
        i_farm.fundRewards(amount);
        s_ghostReserve += amount;
    }

    function _warp(uint256 secondsForward) private {
        vm.warp(block.timestamp + secondsForward);
    }

    function _claim(address account) private returns (uint256 received) {
        uint256 owed = s_ghostOwed[account];
        uint256 expected = owed < s_ghostReserve ? owed : s_ghostReserve;
        uint256 before = i_usdc.balanceOf(account);
        vm.prank(account);
        i_farm.claim();
        received = i_usdc.balanceOf(account) - before;
        assertEq(received, expected);

        s_ghostPaid[account] += received;
        s_ghostOwed[account] -= received;
        s_ghostReserve -= received;
    }

    function _checkpoint(address account) private {
        uint256 earned = _pending(account);
        if (earned != 0) {
            s_ghostEarned[account] += earned;
            s_ghostOwed[account] += earned;
        }
        s_ghostLast[account] = i_clock.currentTime();
    }

    function _pending(address account) private view returns (uint256 pending) {
        uint256 principal = s_ghostPrincipal[account];
        if (principal == 0) return 0;
        uint256 nowTime = i_clock.currentTime();
        uint256 last = s_ghostLast[account];
        if (nowTime <= last) return 0;
        pending = Math.mulDiv(principal, i_aprBps * (nowTime - last), BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    function _account(uint256 actorIndex) private view returns (address account) {
        account = s_actors[bound(actorIndex, 0, s_actors.length - 1)];
    }
}
