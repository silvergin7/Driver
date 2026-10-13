// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../../../src/MockUsdcFaucet.sol";

contract MockUsdcFaucetHandler is Test {
    MockUSDC internal immutable i_token;
    MockUsdcFaucet internal immutable i_faucet;
    address internal immutable i_owner;
    address[] internal s_actors;

    mapping(uint256 day => uint256 count) public s_ghostClaimsPerDay;
    mapping(address actor => uint256 claimedAt) public s_ghostPreviousClaimAt;
    uint256 public s_ghostBusiestDay;
    uint256 public s_ghostMinRepeatGap = type(uint256).max;
    uint256 public s_ghostMintedSum;
    uint256 public s_ghostDailyLimitHits;

    constructor(MockUSDC token, MockUsdcFaucet faucet, address owner_, address[] memory actors) {
        i_token = token;
        i_faucet = faucet;
        i_owner = owner_;
        uint256 length = actors.length;
        for (uint256 i = 0; i < length; i++) {
            s_actors.push(actors[i]);
        }
    }

    function ownerMint(uint256 amount, uint256 actorSeed) external {
        amount = bound(amount, 1, 1e12 * 10 ** 6);
        address to = s_actors[actorSeed % s_actors.length];

        vm.prank(i_owner);
        i_token.mint(to, amount);
        s_ghostMintedSum += amount;
    }

    function claim(uint256 actorSeed) external {
        _claim(s_actors[actorSeed % s_actors.length]);
    }

    function claimBurst(uint256 actorSeed) external {
        uint256 start = actorSeed % s_actors.length;
        uint256 burst = i_faucet.i_dailyClaimLimit() + 1;
        for (uint256 i = 0; i < burst; i++) {
            _claim(s_actors[(start + i) % s_actors.length]);
        }
    }

    function transfer(uint256 amount, uint256 fromSeed, uint256 toSeed) external {
        address from = s_actors[fromSeed % s_actors.length];
        address to = s_actors[toSeed % s_actors.length];
        uint256 balance = i_token.balanceOf(from);
        if (balance == 0) return;

        amount = bound(amount, 0, balance);
        vm.prank(from);
        assertTrue(i_token.transfer(to, amount));
    }

    function warpForward(uint256 secondsForward) external {
        secondsForward = bound(secondsForward, 0, 1 hours);
        vm.warp(block.timestamp + secondsForward);
    }

    function _claim(address actor) internal {
        vm.prank(actor);
        try i_faucet.claim() {
            uint256 timestamp = block.timestamp;
            uint256 previous = s_ghostPreviousClaimAt[actor];
            if (previous != 0) {
                uint256 gap = timestamp - previous;
                assertGe(gap, i_faucet.i_claimCooldown());
                s_ghostMinRepeatGap = gap < s_ghostMinRepeatGap ? gap : s_ghostMinRepeatGap;
            }
            s_ghostPreviousClaimAt[actor] = timestamp;

            uint256 day = timestamp / 1 days;
            s_ghostClaimsPerDay[day] += 1;
            if (s_ghostClaimsPerDay[day] > s_ghostClaimsPerDay[s_ghostBusiestDay]) {
                s_ghostBusiestDay = day;
            }

            s_ghostMintedSum += i_faucet.i_claimAmount();
        } catch (bytes memory reason) {
            bytes4 selector = _selector(reason);
            if (selector == MockUsdcFaucet.MockUsdcFaucet__DailyLimitReached.selector) {
                s_ghostDailyLimitHits += 1;
            } else if (selector != MockUsdcFaucet.MockUsdcFaucet__ClaimTooSoon.selector) {
                _bubble(reason);
            }
        }
    }

    function _selector(bytes memory reason) internal pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly {
            selector := mload(add(reason, 32))
        }
    }

    function _bubble(bytes memory reason) internal pure {
        assembly {
            revert(add(reason, 32), mload(reason))
        }
    }
}
