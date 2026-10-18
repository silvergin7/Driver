// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverVoteHandler} from "./handlers/DriverVoteHandler.sol";

/// forge-config: default.invariant.depth = 100
contract DriverVoteInvariantTest is Test {
    DriverVoteHandler internal handler;

    function setUp() public {
        handler = new DriverVoteHandler();
        assertEq(handler.s_lockAfterVote(), 0);
        assertEq(handler.s_revoted(), 0);
        assertEq(handler.s_afterClose(), 0);
        assertEq(handler.s_boundary(), 0);
        assertEq(handler.s_switched(), 0);
        assertEq(handler.s_kept(), 0);
        assertEq(handler.s_mainExit(), 0);
        assertEq(handler.s_afterDelist(), 0);
        assertEq(handler.s_round(), 0);
        assertEq(handler.s_vote().counted(), 0);

        excludeContract(address(handler.s_usdc()));
        excludeContract(address(handler.s_token()));
        excludeContract(address(handler.s_clock()));
        excludeContract(address(handler.s_splitter()));
        excludeContract(address(handler.s_pool()));
        excludeContract(address(handler.s_schedule()));
        excludeContract(address(handler.s_cruiseFarm()));
        excludeContract(address(handler.s_highway()));
        excludeContract(address(handler.s_autobahn()));
        excludeContract(address(handler.s_drift()));
        excludeContract(address(handler.s_cruise()));
        excludeContract(address(handler.s_degen()));
        excludeContract(address(handler.s_vote()));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.lock.selector;
        selectors[1] = handler.unlock.selector;
        selectors[2] = handler.vote.selector;
        selectors[3] = handler.advance.selector;
        selectors[4] = handler.donate.selector;
        selectors[5] = handler.harvest.selector;
        selectors[6] = handler.exitActive.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_LocksMatchGhosts() public view {
        uint256 sum = 0;
        for (uint256 i = 0; i < 3; i++) {
            uint256 ghost = handler.s_lock(i);
            address actor = handler.s_actor(i);
            assertEq(handler.s_vote().locked(actor), ghost);
            if (handler.s_choice(i) != address(0)) {
                assertGe(handler.s_vote().locked(actor), handler.s_lockedAtVote(i));
            }
            sum += ghost;
        }
        assertEq(handler.s_vote().counted(), sum);
    }

    function invariant_TalliesMatchGhosts() public view {
        uint256 rounds = handler.s_round();
        for (uint256 roundId = 0; roundId <= rounds; roundId++) {
            for (uint256 i = 0; i < 3; i++) {
                address farm = handler.s_farm(i);
                assertEq(handler.s_vote().tally(roundId, farm), handler.s_ghostTally(roundId, farm));
            }
        }
    }

    function invariant_ClosedRoundMatchesFormula() public view {
        uint256 roundId = handler.s_round();
        if (roundId == 0) {
            return;
        }
        uint256 closedRound = roundId - 1;
        assertEq(address(handler.s_vote().leader(closedRound)), handler.expectedLeader(closedRound));
        assertEq(address(handler.s_vote().winner(closedRound)), handler.expectedWinner(closedRound));
    }

    function invariant_BalanceIsCountedPlusDirect() public view {
        assertEq(
            handler.s_token().balanceOf(address(handler.s_vote())), handler.s_vote().counted() + handler.s_direct()
        );
    }

    function invariant_RoundMatchesAdvancedTime() public view {
        assertEq(handler.s_schedule().currentRound(), handler.s_round());
    }

    function afterInvariant() public view {
        assertGt(handler.s_lockAfterVote(), 0);
        assertGt(handler.s_revoted(), 0);
        assertGt(handler.s_afterClose(), 0);
        assertGt(handler.s_boundary(), 0);
        assertGt(handler.s_switched(), 0);
        assertGt(handler.s_kept(), 0);
        assertGt(handler.s_mainExit(), 0);
        assertGt(handler.s_afterDelist(), 0);
    }
}
