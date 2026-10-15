// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IDriverClock} from "./interfaces/IDriverClock.sol";

/// @title Demo Driver clock
/// @notice Demo clock. {currentTime} returns `block.timestamp` plus an owner-controlled offset.
/// @dev The offset only increases. {advanceTime} is owner-only and rejects zero and any step above
/// {MAX_ADVANCE}. Addition uses checked math. This contract never calls another contract, so it does
/// not use `ReentrancyGuard`. Renouncing ownership freezes the offset.
contract DemoDriverClock is IDriverClock, Ownable2Step {
    /// @notice Largest single step {advanceTime} accepts.
    /// @dev Hard-coded because an advance cannot be undone, and later contracts narrow timestamps with `SafeCast`.
    uint256 public constant MAX_ADVANCE = 365 days;

    uint256 private s_offset;

    /// @notice Emitted when the owner advances the demo clock.
    /// @param secondsForward Seconds added to the offset.
    /// @param newOffset Offset after this advance.
    event TimeAdvanced(uint256 secondsForward, uint256 newOffset);

    /// @notice The advance was zero.
    error DemoDriverClock__ZeroSeconds();

    /// @notice The advance was above {MAX_ADVANCE}.
    /// @param secondsForward Seconds the caller tried to add.
    /// @param maxSeconds The largest accepted step.
    error DemoDriverClock__AdvanceTooLarge(uint256 secondsForward, uint256 maxSeconds);

    /// @notice Sets the owner. The offset starts at zero.
    /// @param initialOwner Account allowed to advance the clock. The zero address is rejected.
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Moves the demo clock forward by `secondsForward`.
    /// @dev Reverts with {DemoDriverClock__ZeroSeconds} when `secondsForward` is zero, and with
    /// {DemoDriverClock__AdvanceTooLarge} when it is above {MAX_ADVANCE}. The offset is increased with
    /// checked math. Only the owner may call this.
    /// @param secondsForward Seconds to add to the offset. Must be greater than zero and at most {MAX_ADVANCE}.
    function advanceTime(uint256 secondsForward) external onlyOwner {
        if (secondsForward == 0) {
            revert DemoDriverClock__ZeroSeconds();
        }
        if (secondsForward > MAX_ADVANCE) {
            revert DemoDriverClock__AdvanceTooLarge(secondsForward, MAX_ADVANCE);
        }
        uint256 newOffset = s_offset + secondsForward;
        s_offset = newOffset;
        emit TimeAdvanced(secondsForward, newOffset);
    }

    /// @notice Returns `block.timestamp` plus the offset.
    /// @return currentTime_ Demo time in seconds.
    function currentTime() external view returns (uint256 currentTime_) {
        currentTime_ = block.timestamp + s_offset;
    }

    /// @notice Returns the seconds added on top of `block.timestamp`.
    /// @return offset_ The stored offset. Zero until the first advance.
    function offset() external view returns (uint256 offset_) {
        offset_ = s_offset;
    }
}
