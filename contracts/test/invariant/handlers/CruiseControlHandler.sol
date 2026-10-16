// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CruiseControl} from "../../../src/CruiseControl.sol";
import {DemoDriverClock} from "../../../src/DemoDriverClock.sol";
import {MockFarm} from "../../../src/MockFarm.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";

contract CruiseControlHandler is Test {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    uint256 internal constant MAX_AMOUNT = 1e15;
    uint256 internal constant MAX_WARP = 365 days;

    MockUSDC internal s_usdc;
    DemoDriverClock internal s_clock;
    CruiseControl internal s_fund;
    MockFarm internal s_farmA;
    MockFarm internal s_farmB;
    address internal s_owner;
    address internal s_farmOwner;
    address internal s_stranger;

    uint256[2] internal s_apr;
    uint256[2] internal s_accrued;
    uint256[2] internal s_last;
    bool internal s_hasActive;
    uint256 internal s_active;

    uint256 public s_ghostIdle;
    uint256 public s_ghostPrincipal;
    uint256 public s_ghostHeldRewards;
    uint256 public s_ghostDonated;
    uint256[2] public s_ghostReserve;
    uint256 public s_mintedToOwner;
    uint256 public s_suppliedByOwner;
    uint256 public s_mintedToStranger;
    uint256 public s_suppliedByStranger;

    uint256 public s_ghostSupplies;
    uint256 public s_ghostDeposits;
    uint256 public s_ghostSwitches;
    uint256 public s_ghostFundReserves;
    uint256 public s_ghostPaidSwitches;
    uint256 public s_ghostCappedSwitches;
    uint256 public s_ghostDonations;
    uint256 public s_ghostWarps;
    uint256 public s_ghostAdvances;
    uint256 public s_ghostUnauthorized;

    error CruiseControlHandler__UnauthorizedSupplySucceeded();
    error CruiseControlHandler__PaidSwitchMismatch(uint256 paid, uint256 owed);
    error CruiseControlHandler__CappedSwitchMismatch(uint256 paid, uint256 owed, uint256 reserve);

    constructor(
        MockUSDC usdc,
        DemoDriverClock clock,
        CruiseControl fund,
        MockFarm farmA,
        MockFarm farmB,
        address owner_,
        address farmOwner_,
        address stranger_,
        uint256 reserveAmount,
        uint256 strangerMint
    ) {
        s_usdc = usdc;
        s_clock = clock;
        s_fund = fund;
        s_farmA = farmA;
        s_farmB = farmB;
        s_owner = owner_;
        s_farmOwner = farmOwner_;
        s_stranger = stranger_;
        s_apr[0] = farmA.aprBps();
        s_apr[1] = farmB.aprBps();
        _fundReserve(farmA, 0, reserveAmount);
        _fundReserve(farmB, 1, reserveAmount);
        vm.prank(owner_);
        usdc.mint(stranger_, strangerMint);
        s_mintedToStranger = strangerMint;
    }

    function supply(uint256 amount) external {
        amount = bound(amount, 1, MAX_AMOUNT);
        _supply(amount);
        s_ghostSupplies += 1;
    }

    function deposit(uint256 amount) external {
        if (!s_hasActive) {
            _activate(0);
        }
        if (s_ghostIdle == 0) {
            _supply(bound(amount, 1, MAX_AMOUNT));
        }
        amount = bound(amount, 1, s_ghostIdle);
        _deposit(amount);
        s_ghostDeposits += 1;
    }

    function switchFarm(uint256 amount) external {
        if (!s_hasActive) {
            _activate(0);
        }
        if (s_ghostPrincipal == 0) {
            if (s_ghostIdle == 0) {
                _supply(bound(amount, 1, MAX_AMOUNT));
            }
            _deposit(s_ghostIdle);
        }
        _switchTo(s_active == 0 ? 1 : 0);
        s_ghostSwitches += 1;
    }

    function fundReserve(uint256 index, uint256 amount) external {
        index = bound(index, 0, 1);
        amount = bound(amount, 1, MAX_AMOUNT);
        _fundReserve(_farm(index), index, amount);
        s_ghostFundReserves += 1;
    }

    function paidSwitch(uint256 amount) external {
        _ensurePrincipal(amount);
        if (_owed(s_active) == 0) {
            _accrueAtLeastOne();
        }
        uint256 owed = _owed(s_active);
        uint256 reserve = s_ghostReserve[s_active];
        if (reserve < owed) {
            _fundReserve(_farm(s_active), s_active, owed - reserve);
        }
        (uint256 paid, uint256 settled) = _switchTo(s_active == 0 ? 1 : 0);
        if (paid != settled || settled == 0) {
            revert CruiseControlHandler__PaidSwitchMismatch(paid, settled);
        }
        s_ghostPaidSwitches += 1;
    }

    function cappedSwitch(uint256 amount) external {
        _ensurePrincipal(amount);
        if (_owed(s_active) <= s_ghostReserve[s_active]) {
            _pushOwedPastReserve();
        }
        uint256 reserve = s_ghostReserve[s_active];
        (uint256 paid, uint256 owed) = _switchTo(s_active == 0 ? 1 : 0);
        if (reserve == 0) {
            if (paid != 0 || owed == 0) {
                revert CruiseControlHandler__CappedSwitchMismatch(paid, owed, reserve);
            }
        } else if (paid == 0 || paid >= owed) {
            revert CruiseControlHandler__CappedSwitchMismatch(paid, owed, reserve);
        }
        s_ghostCappedSwitches += 1;
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1, MAX_AMOUNT);
        vm.prank(s_owner);
        s_usdc.mint(address(this), amount);
        s_usdc.transfer(address(s_fund), amount);
        s_ghostDonated += amount;
        s_ghostDonations += 1;
    }

    function warpForward(uint256 secondsForward) external {
        secondsForward = bound(secondsForward, 1, MAX_WARP);
        vm.warp(block.timestamp + secondsForward);
        s_ghostWarps += 1;
    }

    function advanceTime(uint256 secondsForward) external {
        secondsForward = bound(secondsForward, 1, s_clock.MAX_ADVANCE());
        vm.prank(s_owner);
        s_clock.advanceTime(secondsForward);
        s_ghostAdvances += 1;
    }

    function unauthorizedSupply(uint256 amount) external {
        amount = bound(amount, 1, MAX_AMOUNT);
        vm.prank(s_stranger);
        try s_fund.supply(amount) {
            revert CruiseControlHandler__UnauthorizedSupplySucceeded();
        } catch (bytes memory reason) {
            if (_selector(reason) != Ownable.OwnableUnauthorizedAccount.selector) {
                _bubble(reason);
            }
        }
        s_ghostUnauthorized += 1;
    }

    function ghostPendingRewards() external view returns (uint256 pending) {
        if (!s_hasActive) return 0;
        pending = _pending(s_active, s_ghostPrincipal);
    }

    function _supply(uint256 amount) private {
        vm.prank(s_owner);
        s_usdc.mint(s_owner, amount);
        s_mintedToOwner += amount;
        vm.prank(s_owner);
        s_fund.supply(amount);
        s_ghostIdle += amount;
        s_suppliedByOwner += amount;
    }

    function _deposit(uint256 amount) private {
        _checkpoint(s_active, s_ghostPrincipal);
        vm.prank(s_owner);
        s_fund.deposit(amount);
        s_ghostIdle -= amount;
        s_ghostPrincipal += amount;
    }

    function _ensurePrincipal(uint256 amount) private {
        if (!s_hasActive) {
            _activate(0);
        }
        if (s_ghostPrincipal != 0) return;
        if (s_ghostIdle == 0) {
            _supply(bound(amount, 1, MAX_AMOUNT));
        }
        _deposit(s_ghostIdle);
    }

    function _activate(uint256 index) private {
        vm.prank(s_owner);
        s_fund.setStrategy(_farm(index));
        s_active = index;
        s_hasActive = true;
    }

    function _accrueAtLeastOne() private {
        uint256 apr = s_apr[s_active];
        uint256 step = s_clock.MAX_ADVANCE();
        uint256 rate = apr * step;
        uint256 principal = s_ghostPrincipal;
        uint256 earnedAtMax = principal == 0 ? 0 : Math.mulDiv(principal, rate, BPS_DENOMINATOR * SECONDS_PER_YEAR);
        if (earnedAtMax == 0) {
            uint256 minPrincipal = _ceilDiv(BPS_DENOMINATOR * SECONDS_PER_YEAR, rate);
            uint256 extra = minPrincipal - principal;
            if (s_ghostIdle < extra) {
                _supply(extra - s_ghostIdle);
            }
            _deposit(extra);
            principal = s_ghostPrincipal;
        }
        step = _ceilDiv(BPS_DENOMINATOR * SECONDS_PER_YEAR, principal * apr);
        if (step > s_clock.MAX_ADVANCE()) {
            step = s_clock.MAX_ADVANCE();
        }
        _advance(step);
    }

    function _pushOwedPastReserve() private {
        uint256 owed = _owed(s_active);
        uint256 reserve = s_ghostReserve[s_active];
        if (owed > reserve) return;

        uint256 step = s_clock.MAX_ADVANCE();
        uint256 rate = s_apr[s_active] * step;
        uint256 principal = s_ghostPrincipal;
        uint256 fromExisting = principal == 0 ? 0 : Math.mulDiv(principal, rate, BPS_DENOMINATOR * SECONDS_PER_YEAR);
        uint256 need = reserve - owed + 1;
        if (fromExisting < need) {
            uint256 extra = _ceilDiv((need - fromExisting) * BPS_DENOMINATOR * SECONDS_PER_YEAR, rate);
            if (s_ghostIdle < extra) {
                _supply(extra - s_ghostIdle);
            }
            _deposit(extra);
        }
        _advance(step);
    }

    function _advance(uint256 secondsForward) private {
        vm.prank(s_owner);
        s_clock.advanceTime(secondsForward);
    }

    function _switchTo(uint256 next) private returns (uint256 paid, uint256 owed) {
        uint256 previous = s_active;
        uint256 principal = s_ghostPrincipal;

        _checkpoint(previous, principal);
        owed = s_accrued[previous];
        uint256 reserve = s_ghostReserve[previous];
        paid = owed < reserve ? owed : reserve;
        s_accrued[previous] = owed - paid;
        s_ghostReserve[previous] = reserve - paid;
        s_ghostHeldRewards += paid;

        _checkpoint(previous, principal);
        _checkpoint(next, 0);
        s_active = next;

        vm.prank(s_owner);
        s_fund.setStrategy(_farm(next));
    }

    function _fundReserve(MockFarm farm, uint256 index, uint256 amount) private {
        vm.prank(s_owner);
        s_usdc.mint(s_farmOwner, amount);
        vm.startPrank(s_farmOwner);
        s_usdc.approve(address(farm), amount);
        farm.fundRewards(amount);
        vm.stopPrank();
        s_ghostReserve[index] += amount;
    }

    function _checkpoint(uint256 index, uint256 principal) private {
        uint256 nowTime = s_clock.currentTime();
        if (principal != 0 && nowTime > s_last[index]) {
            uint256 earned = _earned(principal, s_apr[index], nowTime - s_last[index]);
            if (earned != 0) {
                s_accrued[index] += earned;
            }
        }
        s_last[index] = nowTime;
    }

    function _owed(uint256 index) private view returns (uint256 owed) {
        uint256 principal = s_hasActive && s_active == index ? s_ghostPrincipal : 0;
        owed = _pending(index, principal);
    }

    function _pending(uint256 index, uint256 principal) private view returns (uint256 pending) {
        pending = s_accrued[index];
        if (principal == 0) return pending;
        uint256 nowTime = s_clock.currentTime();
        uint256 last = s_last[index];
        if (nowTime <= last) return pending;
        pending += _earned(principal, s_apr[index], nowTime - last);
    }

    function _ceilDiv(uint256 numerator, uint256 denominator) private pure returns (uint256 result) {
        result = (numerator + denominator - 1) / denominator;
    }

    function _earned(uint256 principal, uint256 aprBps, uint256 elapsed) private pure returns (uint256 earned) {
        earned = Math.mulDiv(principal, aprBps * elapsed, BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    function _farm(uint256 index) private view returns (MockFarm farm) {
        farm = index == 0 ? s_farmA : s_farmB;
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly {
            selector := mload(add(reason, 32))
        }
    }

    function _bubble(bytes memory reason) private pure {
        assembly {
            revert(add(reason, 32), mload(reason))
        }
    }
}
