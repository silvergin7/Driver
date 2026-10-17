// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "./IDriverClock.sol";
import {IMockFarm} from "./IMockFarm.sol";
import {IOfficialPool} from "./IOfficialPool.sol";
import {MockUSDC} from "../MockUSDC.sol";
import {RoundSchedule} from "../RoundSchedule.sol";
import {TaxSplitter} from "../TaxSplitter.sol";

/// @title Treasury fund
/// @notice Views for one treasury fund. Harvest, rebalance, and voting read this interface.
/// @dev The farm list is fixed in the fund's constructor. This interface has no function that sets the active farm.
interface ITreasuryFund {
    /// @notice Amounts from the latest harvest. Every field is zero before the first harvest.
    struct Harvest {
        uint256 roundId;
        uint256 taxReleased;
        uint256 rewards;
        uint256 compounded;
        uint256 buybackSpent;
        uint256 dvrBurned;
        uint256 pendingBuyback;
    }

    /// @notice Returns mUSDC waiting to be deposited.
    /// @return idle_ Idle balance, in base units.
    function idle() external view returns (uint256 idle_);

    /// @notice Returns farm rewards already claimed and waiting for harvest.
    /// @return heldRewards_ Claimed rewards, in base units.
    function heldRewards() external view returns (uint256 heldRewards_);

    /// @notice Returns the farm that currently holds this fund's principal.
    /// @return farm_ The active farm. The zero address means no farm has been selected.
    function activeFarm() external view returns (IMockFarm farm_);

    /// @notice Returns principal on the active farm.
    /// @return principal_ mUSDC principal, in base units. Zero when no farm is active.
    function principal() external view returns (uint256 principal_);

    /// @notice Returns idle mUSDC plus principal on the active farm.
    /// @dev Held rewards, unpaid farm rewards, and mUSDC sent here directly are not included.
    /// @return value_ Fund value, in base units.
    function value() external view returns (uint256 value_);

    /// @notice Returns unpaid rewards on the active farm.
    /// @dev This is the farm's uncapped accrued view. It is not capped by the reward reserve.
    /// @return rewards_ Unpaid mUSDC, in base units. Zero when no farm is active.
    function pendingRewards() external view returns (uint256 rewards_);

    /// @notice Returns the closed round the next harvest will apply, or the open round when none is ready.
    /// @dev `ready_` is false while round 0 is open and after the latest closed round has already been harvested.
    /// `roundId_` is that closed round when `ready_` is true, and {RoundSchedule.currentRound} otherwise.
    /// @return ready_ True when {harvest} can apply a closed round.
    /// @return roundId_ The round {harvest} will store, or the open round when `ready_` is false.
    function harvestableRound() external view returns (bool ready_, uint256 roundId_);

    /// @notice Returns the last round this fund harvested.
    /// @dev `harvested_` is false before the first harvest. Round 0 is a real id, so the bool is the sentinel.
    /// @return harvested_ True after at least one harvest.
    /// @return roundId_ The stored round. Zero when `harvested_` is false.
    function lastHarvestedRound() external view returns (bool harvested_, uint256 roundId_);

    /// @notice Returns DVR this fund has bought and burned.
    /// @dev This total only increases when a harvest burns buyback output. User burns are not included.
    /// @return burned_ Cumulative DVR burned by this fund, in base units.
    function dvrBoughtBack() external view returns (uint256 burned_);

    /// @notice Returns mUSDC waiting for a later buyback.
    /// @dev A buyback half of zero does not change this. A half that the pool rejects as zero input or zero
    /// output is added here and is not swapped.
    /// @return pending_ Deferred mUSDC, in base units.
    function pendingBuyback() external view returns (uint256 pending_);

    /// @notice Returns the amounts stored by the latest harvest.
    /// @return harvest_ Latest harvest. Every field is zero before the first harvest.
    function lastHarvest() external view returns (Harvest memory harvest_);

    /// @notice Returns whether `farm` was passed to the constructor.
    /// @param farm Account to query.
    /// @return allowed_ True when `farm` is on this fund's list.
    function isStrategy(address farm) external view returns (bool allowed_);

    /// @notice Returns how many farms the constructor listed.
    /// @return count_ Length of the farm list.
    function strategyCount() external view returns (uint256 count_);

    /// @notice Returns the farm at `index` in constructor order.
    /// @param index Position in the list, starting at zero.
    /// @return farm_ The listed farm.
    function strategyAt(uint256 index) external view returns (IMockFarm farm_);

    /// @notice Returns the mUSDC this fund accounts for.
    /// @return usdc_ Mock USDC.
    function i_usdc() external view returns (MockUSDC usdc_);

    /// @notice Returns the clock this fund stores.
    /// @return clock_ Shared clock.
    function i_clock() external view returns (IDriverClock clock_);

    /// @notice Returns the splitter whose bucket this fund will release.
    /// @return splitter_ Tax splitter.
    function i_taxSplitter() external view returns (TaxSplitter splitter_);

    /// @notice Returns the official pool stored for a later buyback.
    /// @return pool_ Official pool.
    function i_pool() external view returns (IOfficialPool pool_);

    /// @notice Returns which splitter bucket this fund releases.
    /// @return fundId_ Fund 1 or Fund 2.
    function i_fundId() external view returns (TaxSplitter.FundId fundId_);

    /// @notice Returns the round schedule this fund harvests against.
    /// @return schedule_ Shared schedule.
    function i_schedule() external view returns (RoundSchedule schedule_);
}
