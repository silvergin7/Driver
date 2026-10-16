// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";

/// @title Halting driver clock
/// @notice Test clock that returns a stored time until {halt}, then reverts.
contract HaltingDriverClock is IDriverClock {
    uint256 private s_time = 1;
    bool private s_halted;

    /// @notice {currentTime} was called after {halt}.
    error HaltingDriverClock__Halted();

    /// @notice Replaces the time returned by {currentTime} before {halt}.
    /// @param newTime Time in seconds.
    function setTime(uint256 newTime) external {
        s_time = newTime;
    }

    /// @notice Makes later {currentTime} calls revert.
    function halt() external {
        s_halted = true;
    }

    /// @notice Returns the stored time, or reverts after {halt}.
    /// @return currentTime_ Stored time in seconds.
    function currentTime() external view returns (uint256 currentTime_) {
        if (s_halted) {
            revert HaltingDriverClock__Halted();
        }
        currentTime_ = s_time;
    }
}
