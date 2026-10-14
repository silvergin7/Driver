// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverFaucet} from "../../src/DriverFaucet.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DriverFaucetFuzzTest is Test {
    DriverToken internal token;
    DriverFaucet internal faucet;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        HelperConfig helper = new HelperConfig();
        token = new DriverToken(owner);
        faucet = new DriverFaucet(
            token,
            helper.DVR_FAUCET_CLAIM_AMOUNT(),
            helper.DVR_FAUCET_CLAIM_COOLDOWN(),
            helper.DVR_FAUCET_DAILY_CLAIM_LIMIT()
        );
        vm.startPrank(owner);
        token.mint(owner, helper.FAUCET_ALLOCATION());
        assertTrue(token.transfer(address(faucet), helper.FAUCET_ALLOCATION()));
        vm.stopPrank();
    }

    function testFuzz_ClaimAllowedExactlyWhenCooldownHasElapsed(uint256 elapsed) public {
        uint256 claimedAt = block.timestamp;
        vm.prank(alice);
        faucet.claim();

        elapsed = bound(elapsed, 0, 10 days);
        vm.warp(claimedAt + elapsed);

        if (elapsed >= faucet.i_claimCooldown()) {
            vm.prank(alice);
            faucet.claim();
            assertEq(token.balanceOf(alice), 2 * faucet.i_claimAmount());
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    DriverFaucet.DriverFaucet__ClaimTooSoon.selector, claimedAt + faucet.i_claimCooldown()
                )
            );
            vm.prank(alice);
            faucet.claim();
            assertEq(token.balanceOf(alice), faucet.i_claimAmount());
        }
    }

    function testFuzz_DailyCountResetsOnlyOnANewUtcDay(uint256 elapsed) public {
        uint256 claimedAt = block.timestamp;
        uint256 resetAt = (claimedAt / 1 days) * 1 days + 1 days;
        for (uint256 i = 0; i < faucet.i_dailyClaimLimit(); i++) {
            vm.prank(address(uint160(i + 1)));
            faucet.claim();
        }

        elapsed = bound(elapsed, 0, 3 days);
        vm.warp(claimedAt + elapsed);

        if (block.timestamp < resetAt) {
            assertEq(faucet.claimsToday(), faucet.i_dailyClaimLimit());
        } else {
            assertEq(faucet.claimsToday(), 0);
        }
    }

    function testFuzz_SuccessfulClaimsDecreaseFaucetBalanceByClaimAmount(uint8 walletCount) public {
        uint256 supply = token.totalSupply();
        uint256 faucetBefore = token.balanceOf(address(faucet));
        walletCount = uint8(bound(walletCount, 0, faucet.i_dailyClaimLimit()));

        for (uint256 i = 0; i < walletCount; i++) {
            vm.prank(address(uint160(i + 1)));
            faucet.claim();
        }

        assertEq(token.balanceOf(address(faucet)), faucetBefore - uint256(walletCount) * faucet.i_claimAmount());
        assertEq(token.totalSupply(), supply);
    }

    function testFuzz_ClaimRevertsWhenBalanceIsBelowOneClaim(uint256 dust) public {
        uint256 amount = faucet.i_claimAmount();
        dust = bound(dust, 0, amount - 1);
        DriverFaucet dry = new DriverFaucet(token, amount, faucet.i_claimCooldown(), faucet.i_dailyClaimLimit());
        if (dust > 0) {
            vm.prank(owner);
            token.mint(address(dry), dust);
        }

        vm.expectRevert(abi.encodeWithSelector(DriverFaucet.DriverFaucet__InsufficientBalance.selector, dust, amount));
        vm.prank(alice);
        dry.claim();

        assertEq(token.balanceOf(address(dry)), dust);
        assertEq(token.balanceOf(alice), 0);
    }
}
