// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "./interfaces/IDriverClock.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {IOfficialPool} from "./interfaces/IOfficialPool.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {TaxSplitter} from "./TaxSplitter.sol";
import {TreasuryFund} from "./TreasuryFund.sol";

/// @title Cruise Control
/// @notice Fund 1. The owner chooses the active farm from the constructor list.
/// @dev A later safe farm is a longer constructor list on a later deploy. This contract has no function
/// that appends a farm. The splitter bucket is Fund 1.
contract CruiseControl is TreasuryFund {
    /// @notice Stores Fund 1's addresses and its farm list.
    /// @param usdc Mock USDC this fund holds. The zero address is rejected.
    /// @param clock Clock stored for a later harvest. The zero address is rejected.
    /// @param taxSplitter Splitter whose Fund 1 bucket this fund will release. The zero address is rejected.
    /// @param pool Official pool stored for a later buyback. The zero address is rejected.
    /// @param farms Farms the owner may select. The deploy passes Cruise alone.
    /// @param initialOwner Account allowed to supply, deposit, and set the farm. The zero address is rejected.
    constructor(
        MockUSDC usdc,
        IDriverClock clock,
        TaxSplitter taxSplitter,
        IOfficialPool pool,
        IMockFarm[] memory farms,
        address initialOwner
    ) TreasuryFund(usdc, clock, taxSplitter, pool, TaxSplitter.FundId.Fund1, farms, initialOwner) {}

    /// @notice Points this fund at one farm from its constructor list.
    /// @dev Calls {_switchFarm}. Only the owner may call this. `nonReentrant` covers the farm calls inside
    /// {_switchFarm}.
    /// @param newFarm Listed farm. The zero address is rejected.
    function setStrategy(IMockFarm newFarm) external nonReentrant onlyOwner {
        _switchFarm(newFarm);
    }
}
