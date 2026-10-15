// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "./interfaces/IDriverClock.sol";

/// @title Driver clock
/// @notice Production clock. {currentTime} returns `block.timestamp`.
/// @dev This contract has no state, no owner, and no function that changes time. A deployment cannot
/// gain an advance path later: that path exists only on {DemoDriverClock}, which is a different contract.
contract DriverClock is IDriverClock {
    /// @notice Returns `block.timestamp`.
    /// @return currentTime_ The block timestamp, in seconds.
    function currentTime() external view returns (uint256 currentTime_) {
        currentTime_ = block.timestamp;
    }
}
