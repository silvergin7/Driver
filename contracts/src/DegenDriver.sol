// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "./interfaces/IDriverClock.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {IOfficialPool} from "./interfaces/IOfficialPool.sol";
import {IStrategyBallot} from "./interfaces/IStrategyBallot.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {RoundSchedule} from "./RoundSchedule.sol";
import {TaxSplitter} from "./TaxSplitter.sol";
import {TreasuryFund} from "./TreasuryFund.sol";

/// @title Degen Driver
/// @notice Fund 2. Its active farm stays unset until a harvest applies a vote.
/// @dev This contract does not expose a strategy setter. {harvest} calls {_switchFarm} with the closed
/// round's farm. The ballot is set once. Voting reads the constructor list and does not switch the farm.
/// The splitter bucket is Fund 2.
contract DegenDriver is TreasuryFund {
    /// @notice Ballot whose closed-round farm {harvest} applies.
    IStrategyBallot private s_ballot;

    /// @notice Emitted when the owner sets the ballot.
    /// @param ballot Ballot stored for later harvests.
    event BallotSet(address indexed ballot);

    /// @notice An address argument was zero.
    error DegenDriver__ZeroAddress();

    /// @notice The ballot was already set.
    error DegenDriver__BallotAlreadySet();

    /// @notice The ballot's farm changed between the two reads in one harvest.
    /// @param expected Farm read before the token calls.
    /// @param actual Farm read when the round was applied.
    error DegenDriver__WinnerChanged(address expected, address actual);

    /// @notice Stores Fund 2's addresses and its farm list.
    /// @param usdc Mock USDC this fund holds. The zero address is rejected.
    /// @param clock Clock this fund and its farms read. The zero address is rejected.
    /// @param schedule Shared round schedule. The zero address is rejected.
    /// @param taxSplitter Splitter whose Fund 2 bucket this fund will release. The zero address is rejected.
    /// @param pool Official pool stored for a later buyback. The zero address is rejected.
    /// @param fund1Usdc Fund 1's starting share, in mUSDC base units. Zero is rejected, and it must be
    /// strictly larger than `fund2Usdc`.
    /// @param fund2Usdc Fund 2's starting share, in mUSDC base units. Zero is rejected.
    /// @param farms Farms a later harvest may select. The deploy passes Highway, Autobahn, and Drift.
    /// @param initialOwner Account allowed to supply and deposit. The zero address is rejected.
    constructor(
        MockUSDC usdc,
        IDriverClock clock,
        RoundSchedule schedule,
        TaxSplitter taxSplitter,
        IOfficialPool pool,
        uint256 fund1Usdc,
        uint256 fund2Usdc,
        IMockFarm[] memory farms,
        address initialOwner
    )
        TreasuryFund(
            usdc,
            clock,
            schedule,
            taxSplitter,
            pool,
            TaxSplitter.FundId.Fund2,
            fund1Usdc,
            fund2Usdc,
            farms,
            initialOwner
        )
    {}

    /// @notice Stores the ballot harvest reads. A second call reverts.
    /// @dev Reverts with {DegenDriver__ZeroAddress} when `ballot_` is zero, and with
    /// {DegenDriver__BallotAlreadySet} when a ballot is already stored. Only the owner may call this.
    /// This function does not call the ballot or move tokens.
    /// @param ballot_ Ballot for closed rounds. The zero address is rejected.
    function setBallot(IStrategyBallot ballot_) external onlyOwner {
        if (address(ballot_) == address(0)) {
            revert DegenDriver__ZeroAddress();
        }
        if (address(s_ballot) != address(0)) {
            revert DegenDriver__BallotAlreadySet();
        }
        s_ballot = ballot_;
        emit BallotSet(address(ballot_));
    }

    /// @dev The ballot is read before {harvest} moves tokens. Address zero, or the farm already active, keeps
    /// the current farm.
    function _farmAfterRound(uint256 roundId) internal view override returns (IMockFarm farm_) {
        farm_ = _chosenFarm(roundId);
    }

    /// @dev Reads the ballot again and reverts with {DegenDriver__WinnerChanged} when the farm differs from
    /// `expectedFarm`. A matching new farm goes through {_switchFarm}. A reverting {IStrategyBallot.winner}
    /// reverts this harvest.
    function _applyClosedRound(uint256 roundId, IMockFarm expectedFarm) internal override {
        IMockFarm chosen_ = _chosenFarm(roundId);
        if (address(chosen_) != address(expectedFarm)) {
            revert DegenDriver__WinnerChanged(address(expectedFarm), address(chosen_));
        }
        if (address(chosen_) == address(_activeFarm())) {
            return;
        }
        _switchFarm(chosen_);
    }

    /// @dev Address zero from the ballot, or the farm already active, keeps the current farm.
    function _chosenFarm(uint256 roundId) private view returns (IMockFarm farm_) {
        farm_ = _activeFarm();
        IStrategyBallot ballot_ = s_ballot;
        if (address(ballot_) == address(0)) {
            return farm_;
        }
        IMockFarm winner_ = ballot_.winner(roundId);
        if (address(winner_) == address(0) || address(winner_) == address(farm_)) {
            return farm_;
        }
        return winner_;
    }
}
