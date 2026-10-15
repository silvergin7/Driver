// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Driver clock
/// @notice Read interface for the shared clock.
/// @dev Later contracts store this interface and call {currentTime} instead of `block.timestamp`.
interface IDriverClock {
    /// @notice Returns the time later contracts should use.
    /// @return currentTime_ Timestamp in seconds.
    function currentTime() external view returns (uint256 currentTime_);
}
