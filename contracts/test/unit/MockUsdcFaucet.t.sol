// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../../src/MockUsdcFaucet.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract MockUsdcFaucetTest is Test {
    MockUSDC internal token;
    MockUsdcFaucet internal faucet;
    HelperConfig internal helper;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    event Claimed(address indexed account, uint256 amount);

    function setUp() public {
        helper = new HelperConfig();
        token = new MockUSDC(owner);
        faucet = new MockUsdcFaucet(
            token,
            helper.USDC_FAUCET_CLAIM_AMOUNT(),
            helper.USDC_FAUCET_CLAIM_COOLDOWN(),
            helper.USDC_FAUCET_DAILY_CLAIM_LIMIT()
        );
        vm.prank(owner);
        token.setMinter(address(faucet));
    }

    function test_ConstructorSetsTokenAndParameters() public view {
        assertEq(address(faucet.i_usdc()), address(token));
        assertEq(faucet.i_claimAmount(), helper.USDC_FAUCET_CLAIM_AMOUNT());
        assertEq(faucet.i_claimCooldown(), helper.USDC_FAUCET_CLAIM_COOLDOWN());
        assertEq(faucet.i_dailyClaimLimit(), helper.USDC_FAUCET_DAILY_CLAIM_LIMIT());
    }

    function test_FirstClaimSucceedsAtLowTimestamp() public {
        assertEq(block.timestamp, 1);

        _claim(alice);

        assertEq(block.timestamp, 1);
        assertEq(token.balanceOf(alice), 100 * 10 ** 6);
        assertEq(faucet.claimsToday(), 1);
        assertEq(faucet.nextClaimAt(alice), 1 + faucet.i_claimCooldown());
    }

    function test_ClaimMintsOneHundredUsdc() public {
        _claim(alice);

        assertEq(token.balanceOf(alice), 100 * 10 ** 6);
        assertEq(token.totalSupply(), 100 * 10 ** 6);
    }

    function test_ClaimEmitsClaimed() public {
        vm.expectEmit(address(faucet));
        emit Claimed(alice, 100 * 10 ** 6);

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

        _claimMany(25);

        assertEq(faucet.claimsToday(), 25);
        assertEq(token.totalSupply(), 25 * faucet.i_claimAmount());
    }

    function test_TwentySixthWalletSucceedsAfterNextUtcMidnight() public {
        _claimMany(25);
        address extra = _wallet(25);

        vm.expectRevert(
            abi.encodeWithSelector(MockUsdcFaucet.MockUsdcFaucet__DailyLimitReached.selector, faucet.nextDailyReset())
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

        vm.expectRevert(abi.encodeWithSelector(MockUsdcFaucet.MockUsdcFaucet__ClaimTooSoon.selector, nextClaimAt));
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

        vm.expectRevert(abi.encodeWithSelector(MockUsdcFaucet.MockUsdcFaucet__ClaimTooSoon.selector, nextClaimAt));
        _claim(alice);

        assertEq(faucet.nextClaimAt(alice), nextClaimAt);
        assertEq(faucet.claimsToday(), claimsToday);
        assertEq(token.balanceOf(alice), faucet.i_claimAmount());
    }

    function test_FaucetTokenBalanceStaysZero() public {
        _claim(alice);

        assertEq(token.balanceOf(address(faucet)), 0);
    }

    function test_SameWalletCannotFillTheDailyLimit() public {
        _claim(alice);

        vm.expectRevert(
            abi.encodeWithSelector(MockUsdcFaucet.MockUsdcFaucet__ClaimTooSoon.selector, faucet.nextClaimAt(alice))
        );
        _claim(alice);

        assertEq(faucet.claimsToday(), 1);
        assertLt(faucet.claimsToday(), faucet.i_dailyClaimLimit());
    }

    function test_RevertWhen_ClaimDuringCooldown() public {
        _claim(alice);

        vm.expectRevert(
            abi.encodeWithSelector(MockUsdcFaucet.MockUsdcFaucet__ClaimTooSoon.selector, faucet.nextClaimAt(alice))
        );
        _claim(alice);

        assertEq(token.balanceOf(alice), faucet.i_claimAmount());
    }

    function test_RevertWhen_DailyLimitReached() public {
        _claimMany(25);
        address extra = _wallet(25);
        uint256 resetAt = faucet.nextDailyReset();

        vm.expectRevert(abi.encodeWithSelector(MockUsdcFaucet.MockUsdcFaucet__DailyLimitReached.selector, resetAt));
        _claim(extra);

        assertEq(token.balanceOf(extra), 0);
        assertEq(faucet.claimsToday(), 25);
        assertEq(token.totalSupply(), 25 * faucet.i_claimAmount());
    }

    function test_RevertWhen_TokenIsZeroAddress() public {
        (uint256 amount, uint256 cooldown, uint256 limit) = _parameters();

        vm.expectRevert(MockUsdcFaucet.MockUsdcFaucet__ZeroAddress.selector);
        new MockUsdcFaucet(MockUSDC(address(0)), amount, cooldown, limit);
    }

    function test_RevertWhen_ClaimAmountIsZero() public {
        (, uint256 cooldown, uint256 limit) = _parameters();

        vm.expectRevert(MockUsdcFaucet.MockUsdcFaucet__ZeroValue.selector);
        new MockUsdcFaucet(token, 0, cooldown, limit);
    }

    function test_RevertWhen_ClaimCooldownIsZero() public {
        (uint256 amount,, uint256 limit) = _parameters();

        vm.expectRevert(MockUsdcFaucet.MockUsdcFaucet__ZeroValue.selector);
        new MockUsdcFaucet(token, amount, 0, limit);
    }

    function test_RevertWhen_DailyClaimLimitIsZero() public {
        (uint256 amount, uint256 cooldown,) = _parameters();

        vm.expectRevert(MockUsdcFaucet.MockUsdcFaucet__ZeroValue.selector);
        new MockUsdcFaucet(token, amount, cooldown, 0);
    }

    function _claim(address account) internal {
        vm.prank(account);
        faucet.claim();
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
        amount = helper.USDC_FAUCET_CLAIM_AMOUNT();
        cooldown = helper.USDC_FAUCET_CLAIM_COOLDOWN();
        limit = helper.USDC_FAUCET_DAILY_CLAIM_LIMIT();
    }
}
