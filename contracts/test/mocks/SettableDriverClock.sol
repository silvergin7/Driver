// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";

/// @title Settable driver clock
/// @notice Test clock whose time can be set, including to an earlier value.
contract SettableDriverClock is IDriverClock {
    uint256 private s_time = 1;

    /// @notice Emitted when the time is replaced.
    /// @param newTime Time stored after the call, in seconds.
    event TimeSet(uint256 newTime);

    /// @notice Replaces the time returned by {currentTime}.
    /// @param newTime Time in seconds. May be earlier than the stored time.
    function setTime(uint256 newTime) external {
        s_time = newTime;
        emit TimeSet(newTime);
    }

    /// @notice Returns the stored time.
    /// @return currentTime_ Stored time in seconds.
    function currentTime() external view returns (uint256 currentTime_) {
        currentTime_ = s_time;
    }
}
