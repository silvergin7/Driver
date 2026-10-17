// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IMockFarm} from "./IMockFarm.sol";

/// @title Strategy ballot
/// @notice The farm a closed round chose for Degen Driver.
/// @dev A later voting contract implements this. Address zero means the current farm stays.
interface IStrategyBallot {
    /// @notice Returns the farm the closed round chose.
    /// @dev Address zero means the caller keeps its current farm. A reverting call blocks that harvest.
    /// @param roundId Closed round the harvest is applying.
    /// @return winner_ Listed farm, or the zero address to keep the current farm.
    function winner(uint256 roundId) external view returns (IMockFarm winner_);
}
