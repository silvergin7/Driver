// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../../src/DriverToken.sol";
import {DriverFaucet} from "../../../src/DriverFaucet.sol";

contract DriverFaucetEmptyHandler is Test {
    DriverToken internal immutable i_token;
    DriverFaucet internal immutable i_faucet;
    address[] internal s_actors;

    mapping(address actor => uint256 claimedAt) public s_ghostPreviousClaimAt;
    uint256 public s_ghostPaidSum;
    uint256 public s_ghostInsufficientBalanceHits;
    uint256 public s_initialFaucetBalance;
    uint256 public s_initialSupply;

    constructor(DriverToken token, DriverFaucet faucet, address[] memory actors) {
        i_token = token;
        i_faucet = faucet;
        s_initialFaucetBalance = token.balanceOf(address(faucet));
        s_initialSupply = token.totalSupply();
        uint256 length = actors.length;
        for (uint256 i = 0; i < length; i++) {
            s_actors.push(actors[i]);
        }
    }

    function claimBurst(uint256 actorSeed) external {
        uint256 length = s_actors.length;
        uint256 start = actorSeed % length;
        uint256 burst = i_faucet.i_dailyClaimLimit() + 1;
        for (uint256 i = 0; i < burst; i++) {
            _claim(s_actors[(start + i) % length]);
        }

        if (i_token.balanceOf(address(i_faucet)) < i_faucet.i_claimAmount()) {
            vm.warp(i_faucet.nextDailyReset());
            _claim(_freshActor((start + burst) % length));
        }
    }

    function _freshActor(uint256 start) internal view returns (address actor) {
        uint256 length = s_actors.length;
        for (uint256 i = 0; i < length; i++) {
            address candidate = s_actors[(start + i) % length];
            if (s_ghostPreviousClaimAt[candidate] == 0) {
                return candidate;
            }
        }
        return address(0);
    }

    function _claim(address actor) internal {
        if (actor == address(0)) return;

        vm.prank(actor);
        try i_faucet.claim() {
            s_ghostPreviousClaimAt[actor] = block.timestamp;
            s_ghostPaidSum += i_faucet.i_claimAmount();
        } catch (bytes memory reason) {
            bytes4 selector = _selector(reason);
            if (selector == DriverFaucet.DriverFaucet__InsufficientBalance.selector) {
                s_ghostInsufficientBalanceHits += 1;
            } else if (
                selector != DriverFaucet.DriverFaucet__DailyLimitReached.selector
                    && selector != DriverFaucet.DriverFaucet__ClaimTooSoon.selector
            ) {
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
