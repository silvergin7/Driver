// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../../src/MockUsdcFaucet.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract MockUsdcFaucetFuzzTest is Test {
    MockUSDC internal token;
    MockUsdcFaucet internal faucet;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        HelperConfig helper = new HelperConfig();
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
                    MockUsdcFaucet.MockUsdcFaucet__ClaimTooSoon.selector, claimedAt + faucet.i_claimCooldown()
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

    function testFuzz_SuccessfulClaimsIncreaseSupplyByClaimAmount(uint8 walletCount) public {
        walletCount = uint8(bound(walletCount, 0, faucet.i_dailyClaimLimit()));

        for (uint256 i = 0; i < walletCount; i++) {
            vm.prank(address(uint160(i + 1)));
            faucet.claim();
        }

        assertEq(token.totalSupply(), uint256(walletCount) * faucet.i_claimAmount());
    }
}
