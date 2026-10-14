// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverFaucet} from "../../src/DriverFaucet.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DriverFaucetTest is Test {
    DriverToken internal token;
    DriverFaucet internal faucet;
    HelperConfig internal helper;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    event Claimed(address indexed account, uint256 amount);

    function setUp() public {
        helper = new HelperConfig();
        token = new DriverToken(owner);
        faucet = _newFaucet();
        _fund(address(faucet), helper.FAUCET_ALLOCATION());
    }

    function test_ConstructorSetsTokenAndParameters() public view {
        assertEq(address(faucet.i_token()), address(token));
        assertEq(faucet.i_claimAmount(), helper.DVR_FAUCET_CLAIM_AMOUNT());
        assertEq(faucet.i_claimCooldown(), helper.DVR_FAUCET_CLAIM_COOLDOWN());
        assertEq(faucet.i_dailyClaimLimit(), helper.DVR_FAUCET_DAILY_CLAIM_LIMIT());
    }

    function test_FirstClaimSucceedsAtLowTimestamp() public {
        assertEq(block.timestamp, 1);
        uint256 faucetBefore = token.balanceOf(address(faucet));

        _claim(alice);

        assertEq(block.timestamp, 1);
        assertEq(token.balanceOf(alice), 10 * 10 ** 18);
        assertEq(token.balanceOf(address(faucet)), faucetBefore - 10 * 10 ** 18);
        assertEq(faucet.claimsToday(), 1);
        assertEq(faucet.nextClaimAt(alice), 1 + faucet.i_claimCooldown());
    }

    function test_ClaimTransfersTenDvr() public {
        uint256 supply = token.totalSupply();
        uint256 minted = token.totalMinted();
        uint256 faucetBefore = token.balanceOf(address(faucet));

        _claim(alice);

        assertEq(token.decimals(), 18);
        assertEq(faucet.i_claimAmount(), 10 * 10 ** 18);
        assertEq(token.balanceOf(alice), 10 * 10 ** 18);
        assertEq(token.balanceOf(address(faucet)), faucetBefore - 10 * 10 ** 18);
        assertEq(token.totalSupply(), supply);
        assertEq(token.totalMinted(), minted);
    }

    function test_ClaimEmitsClaimed() public {
        vm.expectEmit(address(faucet));
        emit Claimed(alice, 10 * 10 ** 18);

        _claim(alice);
    }

    function test_ClaimSetsNextClaimAtAndIncrementsClaimsToday() public {
        _claim(alice);

        assertEq(faucet.nextClaimAt(alice), block.timestamp + faucet.i_claimCooldown());
        assertEq(faucet.claimsToday(), 1);
    }

    function test_SecondClaimSucceedsAfterCooldown() public {
        _claim(alice);
        vm.warp(faucet.nextClaimAt(alice) + 1);

        _claim(alice);

        assertEq(token.balanceOf(alice), 2 * faucet.i_claimAmount());
    }

    function test_ClaimSucceedsAtExactCooldownBoundary() public {
        _claim(alice);
        vm.warp(faucet.nextClaimAt(alice));

        _claim(alice);

        assertEq(token.balanceOf(alice), 2 * faucet.i_claimAmount());
    }

    function test_TwentyFiveDistinctWalletsCanClaimInOneUtcDay() public {
        assertEq(faucet.i_dailyClaimLimit(), 25);
        uint256 faucetBefore = token.balanceOf(address(faucet));

        _claimMany(25);

        assertEq(faucet.claimsToday(), 25);
        assertEq(token.balanceOf(address(faucet)), faucetBefore - 25 * faucet.i_claimAmount());
        assertEq(token.totalSupply(), helper.FAUCET_ALLOCATION());
    }

    function test_TwentySixthWalletSucceedsAfterNextUtcMidnight() public {
        _claimMany(25);
        address extra = _wallet(25);

        vm.expectRevert(
            abi.encodeWithSelector(DriverFaucet.DriverFaucet__DailyLimitReached.selector, faucet.nextDailyReset())
        );
        _claim(extra);

        vm.warp(faucet.nextDailyReset());
        _claim(extra);

        assertEq(token.balanceOf(extra), faucet.i_claimAmount());
        assertEq(faucet.claimsToday(), 1);
    }

    function test_ClaimJustBeforeMidnightDoesNotResetCooldown() public {
        vm.warp(1 days - 1);
        _claim(alice);
        uint256 nextClaimAt = faucet.nextClaimAt(alice);

        vm.warp(1 days);

        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__ClaimTooSoon.selector, nextClaimAt));
        _claim(alice);

        assertEq(token.balanceOf(alice), faucet.i_claimAmount());
        assertEq(faucet.claimsToday(), 0);
        assertEq(faucet.nextClaimAt(alice), nextClaimAt);
    }

    function test_ClaimsTodayReadsZeroAfterUtcMidnightBeforeTheNextClaim() public {
        _claim(alice);
        assertEq(faucet.claimsToday(), 1);

        vm.warp(faucet.nextDailyReset());

        assertEq(faucet.claimsToday(), 0);
        assertEq(token.balanceOf(alice), faucet.i_claimAmount());
    }

    function test_NextDailyResetIsTheNextUtcMidnight() public {
        assertEq(block.timestamp, 1);
        assertEq(faucet.nextDailyReset(), 1 days);

        vm.warp(1 days);
        assertEq(faucet.nextDailyReset(), 2 days);

        vm.warp(2 days - 1);
        assertEq(faucet.nextDailyReset(), 2 days);
    }

    function test_NextClaimAtIsZeroBeforeTheFirstClaim() public view {
        assertEq(faucet.nextClaimAt(alice), 0);
    }

    function test_FailedClaimDoesNotChangeDailyCountOrCooldown() public {
        _claim(alice);
        uint256 nextClaimAt = faucet.nextClaimAt(alice);
        uint256 claimsToday = faucet.claimsToday();
        uint256 balance = token.balanceOf(alice);

        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__ClaimTooSoon.selector, nextClaimAt));
        _claim(alice);

        assertEq(faucet.nextClaimAt(alice), nextClaimAt);
        assertEq(faucet.claimsToday(), claimsToday);
        assertEq(token.balanceOf(alice), balance);
    }

    function test_SameWalletCannotFillTheDailyLimit() public {
        _claim(alice);

        vm.expectRevert(
            abi.encodeWithSelector(DriverFaucet.DriverFaucet__ClaimTooSoon.selector, faucet.nextClaimAt(alice))
        );
        _claim(alice);

        assertEq(faucet.claimsToday(), 1);
        assertLt(faucet.claimsToday(), faucet.i_dailyClaimLimit());
    }

    function test_ClaimSucceedsWhenBalanceEqualsClaimAmount() public {
        DriverFaucet exact = _newFaucet();
        uint256 amount = exact.i_claimAmount();
        _fund(address(exact), amount);

        _claimOn(exact, alice);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(exact)), 0);
    }

    function test_RevertWhen_ClaimDuringCooldown() public {
        _claim(alice);

        vm.expectRevert(
            abi.encodeWithSelector(DriverFaucet.DriverFaucet__ClaimTooSoon.selector, faucet.nextClaimAt(alice))
        );
        _claim(alice);

        assertEq(token.balanceOf(alice), faucet.i_claimAmount());
    }

    function test_RevertWhen_DailyLimitReached() public {
        _claimMany(25);
        address extra = _wallet(25);
        uint256 resetAt = faucet.nextDailyReset();
        uint256 faucetBefore = token.balanceOf(address(faucet));

        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__DailyLimitReached.selector, resetAt));
        _claim(extra);

        assertEq(token.balanceOf(extra), 0);
        assertEq(faucet.claimsToday(), 25);
        assertEq(token.balanceOf(address(faucet)), faucetBefore);
        assertEq(token.totalSupply(), helper.FAUCET_ALLOCATION());
    }

    function test_RevertWhen_BalanceCannotCoverClaim() public {
        DriverFaucet dry = _newFaucet();
        uint256 amount = dry.i_claimAmount();

        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__InsufficientBalance.selector, 0, amount));
        _claimOn(dry, alice);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(dry)), 0);
        assertEq(dry.claimsToday(), 0);
        assertEq(dry.nextClaimAt(alice), 0);

        uint256 dust = amount - 1;
        _fund(address(dry), dust);

        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__InsufficientBalance.selector, dust, amount));
        _claimOn(dry, alice);

        assertEq(token.balanceOf(address(dry)), dust);
        assertEq(token.balanceOf(alice), 0);
        assertEq(dry.claimsToday(), 0);
        assertEq(dry.nextClaimAt(alice), 0);
    }

    function test_RevertWhen_FullDayRevertsBeforeBalance() public {
        DriverFaucet limited = _newFaucet();
        uint256 amount = limited.i_claimAmount();
        _fund(address(limited), limited.i_dailyClaimLimit() * amount);

        for (uint256 i = 0; i < limited.i_dailyClaimLimit(); i++) {
            _claimOn(limited, _wallet(i));
        }
        assertEq(token.balanceOf(address(limited)), 0);
        assertEq(limited.claimsToday(), limited.i_dailyClaimLimit());

        address extra = _wallet(limited.i_dailyClaimLimit());
        uint256 resetAt = limited.nextDailyReset();
        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__DailyLimitReached.selector, resetAt));
        _claimOn(limited, extra);
    }

    function test_RevertWhen_TokenIsZeroAddress() public {
        (uint256 amount, uint256 cooldown, uint256 limit) = _parameters();

        vm.expectRevert(DriverFaucet.DriverFaucet__ZeroAddress.selector);
        new DriverFaucet(DriverToken(address(0)), amount, cooldown, limit);
    }

    function test_RevertWhen_ClaimAmountIsZero() public {
        (, uint256 cooldown, uint256 limit) = _parameters();

        vm.expectRevert(DriverFaucet.DriverFaucet__ZeroValue.selector);
        new DriverFaucet(token, 0, cooldown, limit);
    }

    function test_RevertWhen_ClaimCooldownIsZero() public {
        (uint256 amount,, uint256 limit) = _parameters();

        vm.expectRevert(DriverFaucet.DriverFaucet__ZeroValue.selector);
        new DriverFaucet(token, amount, 0, limit);
    }

    function test_RevertWhen_DailyClaimLimitIsZero() public {
        (uint256 amount, uint256 cooldown,) = _parameters();

        vm.expectRevert(DriverFaucet.DriverFaucet__ZeroValue.selector);
        new DriverFaucet(token, amount, cooldown, 0);
    }

    function _newFaucet() internal returns (DriverFaucet newFaucet) {
        newFaucet = new DriverFaucet(
            token,
            helper.DVR_FAUCET_CLAIM_AMOUNT(),
            helper.DVR_FAUCET_CLAIM_COOLDOWN(),
            helper.DVR_FAUCET_DAILY_CLAIM_LIMIT()
        );
    }

    function _fund(address to, uint256 amount) internal {
        vm.startPrank(owner);
        token.mint(owner, amount);
        assertTrue(token.transfer(to, amount));
        vm.stopPrank();
    }

    function _claim(address account) internal {
        _claimOn(faucet, account);
    }

    function _claimOn(DriverFaucet target, address account) internal {
        vm.prank(account);
        target.claim();
    }

    function _claimMany(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            _claim(_wallet(i));
        }
    }

    function _wallet(uint256 index) internal pure returns (address wallet) {
        wallet = address(uint160(index + 1));
    }

    function _parameters() internal view returns (uint256 amount, uint256 cooldown, uint256 limit) {
        amount = helper.DVR_FAUCET_CLAIM_AMOUNT();
        cooldown = helper.DVR_FAUCET_CLAIM_COOLDOWN();
        limit = helper.DVR_FAUCET_DAILY_CLAIM_LIMIT();
    }
}
