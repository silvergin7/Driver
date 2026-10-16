// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "./interfaces/IDriverClock.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {IOfficialPool} from "./interfaces/IOfficialPool.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {TaxSplitter} from "./TaxSplitter.sol";
import {TreasuryFund} from "./TreasuryFund.sol";

/// @title Degen Driver
/// @notice Fund 2. Its active farm stays unset until a later harvest applies a vote.
/// @dev This contract does not expose a strategy setter. A later harvest calls {_switchFarm} with the closed
/// vote's farm. Voting reads the constructor list and does not switch the farm. The splitter bucket is Fund 2.
contract DegenDriver is TreasuryFund {
    /// @notice Stores Fund 2's addresses and its farm list.
    /// @param usdc Mock USDC this fund holds. The zero address is rejected.
    /// @param clock Clock stored for a later harvest. The zero address is rejected.
    /// @param taxSplitter Splitter whose Fund 2 bucket this fund will release. The zero address is rejected.
    /// @param pool Official pool stored for a later buyback. The zero address is rejected.
    /// @param farms Farms a later harvest may select. The deploy passes Highway, Autobahn, and Drift.
    /// @param initialOwner Account allowed to supply and deposit. The zero address is rejected.
    constructor(
        MockUSDC usdc,
        IDriverClock clock,
        TaxSplitter taxSplitter,
        IOfficialPool pool,
        IMockFarm[] memory farms,
        address initialOwner
    ) TreasuryFund(usdc, clock, taxSplitter, pool, TaxSplitter.FundId.Fund2, farms, initialOwner) {}
}
