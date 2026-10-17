// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "./interfaces/IDriverClock.sol";

/// @title Round schedule
/// @notice The shared 30-day rounds that harvest and voting both read.
/// @dev The epoch is fixed in the constructor. Rounds chain by {IDriverClock.currentTime}. No call
/// opens or closes a round. Round 0 starts at construction. A round is closed once the clock reaches
/// its end, and the next round is open at that same timestamp.
contract RoundSchedule {
    /// @notice Shortest epoch the constructor accepts.
    uint256 public constant MIN_EPOCH = 1 days;

    /// @notice Longest epoch the constructor accepts.
    uint256 public constant MAX_EPOCH = 90 days;

    /// @notice Clock this schedule reads.
    IDriverClock public immutable i_clock;

    /// @notice Length of every round, in seconds.
    uint256 public immutable i_epoch;

    /// @notice Clock time at which round 0 opened.
    uint256 public immutable i_start;

    /// @notice Emitted when the schedule stores its start and its epoch.
    /// @param start Clock time at which round 0 opened.
    /// @param epoch Length of every round, in seconds.
    event RoundScheduleStarted(uint256 start, uint256 epoch);

    /// @notice The clock was the zero address.
    error RoundSchedule__ZeroAddress();

    /// @notice The epoch was outside {MIN_EPOCH} and {MAX_EPOCH}.
    /// @param epoch Epoch the caller passed, in seconds.
    /// @param minEpoch Shortest accepted epoch, in seconds.
    /// @param maxEpoch Longest accepted epoch, in seconds.
    error RoundSchedule__EpochOutOfRange(uint256 epoch, uint256 minEpoch, uint256 maxEpoch);

    /// @notice No round has closed yet.
    error RoundSchedule__NoClosedRound();

    /// @notice Stores the clock, the epoch, and the start of round 0.
    /// @dev Reverts with {RoundSchedule__ZeroAddress} when `clock` is zero, and with
    /// {RoundSchedule__EpochOutOfRange} when `epoch` is below {MIN_EPOCH} or above {MAX_EPOCH}.
    /// `i_start` is `clock.currentTime()` read once here. There is no setter.
    /// @param clock Clock later views read. The zero address is rejected.
    /// @param epoch Length of every round, in seconds. Must be from {MIN_EPOCH} to {MAX_EPOCH}.
    constructor(IDriverClock clock, uint256 epoch) {
        if (address(clock) == address(0)) {
            revert RoundSchedule__ZeroAddress();
        }
        if (epoch < MIN_EPOCH || epoch > MAX_EPOCH) {
            revert RoundSchedule__EpochOutOfRange(epoch, MIN_EPOCH, MAX_EPOCH);
        }
        i_clock = clock;
        i_epoch = epoch;
        i_start = clock.currentTime();
        emit RoundScheduleStarted(i_start, epoch);
    }

    /// @notice Returns the round that is open at the clock's current time.
    /// @dev Round 0 is open from {i_start} until {roundEnd} of round 0. A clock time before {i_start}
    /// underflows. Neither Driver clock moves backwards.
    /// @return roundId_ The open round, starting at zero.
    function currentRound() public view returns (uint256 roundId_) {
        roundId_ = (i_clock.currentTime() - i_start) / i_epoch;
    }

    /// @notice Returns the clock time at which `roundId` opens.
    /// @param roundId Round to query, starting at zero.
    /// @return start_ Opening timestamp. Round 0 opens at {i_start}.
    function roundStart(uint256 roundId) external view returns (uint256 start_) {
        start_ = i_start + roundId * i_epoch;
    }

    /// @notice Returns the first clock time at which `roundId` is closed.
    /// @dev The next round opens at this same timestamp.
    /// @param roundId Round to query, starting at zero.
    /// @return end_ Closing timestamp.
    function roundEnd(uint256 roundId) external view returns (uint256 end_) {
        end_ = i_start + (roundId + 1) * i_epoch;
    }

    /// @notice Returns the newest round that has already closed.
    /// @dev Reverts with {RoundSchedule__NoClosedRound} while round 0 is still open. Every round id
    /// below {currentRound} is closed.
    /// @return roundId_ The newest closed round.
    function latestClosedRound() external view returns (uint256 roundId_) {
        uint256 openRound = currentRound();
        if (openRound == 0) {
            revert RoundSchedule__NoClosedRound();
        }
        roundId_ = openRound - 1;
    }
}
