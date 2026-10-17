// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDriverClock} from "./interfaces/IDriverClock.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {IOfficialPool} from "./interfaces/IOfficialPool.sol";
import {DegenDriver} from "./DegenDriver.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {RoundSchedule} from "./RoundSchedule.sol";
import {TaxSplitter} from "./TaxSplitter.sol";
import {TreasuryFund} from "./TreasuryFund.sol";

/// @title Cruise Control
/// @notice Fund 1. The owner chooses the active farm from the constructor list.
/// @dev A later safe farm is a longer constructor list on a later deploy. This contract has no function
/// that appends a farm. The splitter bucket is Fund 1.
contract CruiseControl is TreasuryFund {
    using SafeERC20 for IERC20;

    /// @notice Fund 2. Zero until {setFund2}. The setter runs once.
    DegenDriver private s_fund2;

    /// @notice Emitted when the owner stores Fund 2.
    /// @param fund2 Fund 2 stored for the top-up.
    event Fund2Set(address indexed fund2);

    /// @notice Emitted when the owner moves mUSDC from this fund to Fund 2.
    /// @param amount mUSDC moved, in base units.
    /// @param fund1Value This fund's value before the move, in mUSDC base units.
    /// @param fund2Value Fund 2's value before the move, in mUSDC base units.
    /// @param reason Reason supplied by the owner. It is not stored.
    event Fund2ToppedUp(uint256 amount, uint256 fund1Value, uint256 fund2Value, string reason);

    /// @notice Fund 2 was already stored.
    error CruiseControl__Fund2AlreadySet();

    /// @notice The caller is not the stored Fund 2.
    /// @param caller Account that called the function.
    error CruiseControl__NotFund2(address caller);

    /// @notice Fund 2 does not point back at this fund, or it does not share this fund's token, clock,
    /// schedule, or starting shares.
    /// @param fund2 Account that was rejected.
    error CruiseControl__Fund2Mismatch(address fund2);

    /// @notice {setFund2} has not been called.
    error CruiseControl__Fund2NotSet();

    /// @notice The top-up reason was an empty string.
    error CruiseControl__EmptyReason();

    /// @notice The top-up is above the amount that restores Fund 2's starting share.
    /// @param cap Largest amount this call could move, in mUSDC base units.
    /// @param amount Amount the caller tried to move, in mUSDC base units.
    error CruiseControl__TopUpAboveCap(uint256 cap, uint256 amount);

    /// @notice Stores Fund 1's addresses and its farm list.
    /// @param usdc Mock USDC this fund holds. The zero address is rejected.
    /// @param clock Clock this fund and its farms read. The zero address is rejected.
    /// @param schedule Shared round schedule. The zero address is rejected.
    /// @param taxSplitter Splitter whose Fund 1 bucket this fund will release. The zero address is rejected.
    /// @param pool Official pool stored for a later buyback. The zero address is rejected.
    /// @param fund1Usdc Fund 1's starting share, in mUSDC base units. Zero is rejected, and it must be
    /// strictly larger than `fund2Usdc`.
    /// @param fund2Usdc Fund 2's starting share, in mUSDC base units. Zero is rejected.
    /// @param farms Farms the owner may select. The deploy passes Cruise alone.
    /// @param initialOwner Account allowed to supply, deposit, and set the farm. The zero address is rejected.
    constructor(
        MockUSDC usdc,
        IDriverClock clock,
        RoundSchedule schedule,
        TaxSplitter taxSplitter,
        IOfficialPool pool,
        uint256 fund1Usdc,
        uint256 fund2Usdc,
        IMockFarm[] memory farms,
        address initialOwner
    )
        TreasuryFund(
            usdc,
            clock,
            schedule,
            taxSplitter,
            pool,
            TaxSplitter.FundId.Fund1,
            fund1Usdc,
            fund2Usdc,
            farms,
            initialOwner
        )
    {}

    /// @notice Stores Fund 2. A second call reverts.
    /// @dev Reverts with {TreasuryFund__ZeroAddress} when `fund2_` is zero, with {CruiseControl__Fund2AlreadySet}
    /// when Fund 2 is already stored, and with {CruiseControl__Fund2Mismatch} unless `fund2_` points back at
    /// this contract and shares its mUSDC, clock, schedule, and starting shares. Those reads happen before
    /// the address is stored. `nonReentrant` covers a callback from `fund2_`. Only the owner may call this.
    /// @param fund2_ Fund 2. The zero address is rejected.
    function setFund2(DegenDriver fund2_) external nonReentrant onlyOwner {
        if (address(fund2_) == address(0)) {
            revert TreasuryFund__ZeroAddress();
        }
        if (address(s_fund2) != address(0)) {
            revert CruiseControl__Fund2AlreadySet();
        }
        if (address(fund2_.i_fund1()) != address(this)) {
            revert CruiseControl__Fund2Mismatch(address(fund2_));
        }
        if (address(fund2_.i_usdc()) != address(i_usdc)) {
            revert CruiseControl__Fund2Mismatch(address(fund2_));
        }
        if (address(fund2_.i_clock()) != address(i_clock)) {
            revert CruiseControl__Fund2Mismatch(address(fund2_));
        }
        if (address(fund2_.i_schedule()) != address(i_schedule)) {
            revert CruiseControl__Fund2Mismatch(address(fund2_));
        }
        if (fund2_.i_fund1Usdc() != i_fund1Usdc || fund2_.i_fund2Usdc() != i_fund2Usdc) {
            revert CruiseControl__Fund2Mismatch(address(fund2_));
        }
        s_fund2 = fund2_;
        emit Fund2Set(address(fund2_));
    }

    /// @notice Pulls a rebalance payment from Fund 2 and puts it to work.
    /// @dev Reverts with {CruiseControl__NotFund2} when the caller is not the stored Fund 2, and with
    /// {TreasuryFund__ZeroAmount} when `amount` is zero. Idle is credited before the pull when no farm is
    /// active. Otherwise the deposit amount is fixed before the pull and the farm deposit. Only Fund 2 may
    /// call this.
    /// @param amount mUSDC to pull, in base units. Must be greater than zero.
    function acceptRebalance(uint256 amount) external nonReentrant {
        if (msg.sender != address(s_fund2)) {
            revert CruiseControl__NotFund2(msg.sender);
        }
        _acceptCapital(amount);
    }

    /// @notice Points this fund at one farm from its constructor list.
    /// @dev Calls {_switchFarm}. Only the owner may call this. `nonReentrant` covers the farm calls inside
    /// {_switchFarm}.
    /// @param newFarm Listed farm. The zero address is rejected.
    function setStrategy(IMockFarm newFarm) external nonReentrant onlyOwner {
        _switchFarm(newFarm);
    }

    /// @notice Moves `amount` of mUSDC to Fund 2, up to Fund 2's starting share.
    /// @dev Reverts with {CruiseControl__Fund2NotSet} before Fund 2 is stored, with
    /// {CruiseControl__EmptyReason} when `reason` is an empty string, with {TreasuryFund__ZeroAmount}
    /// when `amount` is zero, and with {CruiseControl__TopUpAboveCap} when `amount` is above the cap.
    /// A whitespace reason is accepted. This call is not tied to a round. Idle is debited before the
    /// farm withdraw and the Fund 2 call. The event carries the values from before the move. Only the
    /// owner may call this. `nonReentrant` covers the farm and Fund 2 calls.
    /// @param amount mUSDC to move, in base units. Must be greater than zero and no more than the cap.
    /// @param reason Reason recorded in the event. An empty string is rejected.
    function topUpFund2(uint256 amount, string calldata reason) external nonReentrant onlyOwner {
        DegenDriver fund2_ = s_fund2;
        if (address(fund2_) == address(0)) {
            revert CruiseControl__Fund2NotSet();
        }
        if (bytes(reason).length == 0) {
            revert CruiseControl__EmptyReason();
        }
        if (amount == 0) {
            revert TreasuryFund__ZeroAmount();
        }
        uint256 fund1Value = _value();
        uint256 fund2Value = fund2_.value();
        uint256 cap = _amountToMove(i_fund1Usdc, fund1Value, i_fund2Usdc, fund2Value);
        if (amount > cap) {
            revert CruiseControl__TopUpAboveCap(cap, amount);
        }
        uint256 fromIdle = _takeFromIdle(amount);
        uint256 fromFarm = amount - fromIdle;
        if (fromFarm != 0) {
            _activeFarm().withdraw(fromFarm);
        }
        IERC20(i_usdc).forceApprove(address(fund2_), amount);
        fund2_.acceptTopUp(amount);
        IERC20(i_usdc).forceApprove(address(fund2_), 0);
        emit Fund2ToppedUp(amount, fund1Value, fund2Value, reason);
    }

    /// @notice Returns the largest top-up the current values allow.
    /// @dev Reverts with {CruiseControl__Fund2NotSet} before {setFund2}.
    /// @return fund1Value This fund's value, in mUSDC base units.
    /// @return fund2Value Fund 2's value, in mUSDC base units.
    /// @return cap Largest top-up, in mUSDC base units. Zero when Fund 2 is already at or above its share.
    function topUpCap() external view returns (uint256 fund1Value, uint256 fund2Value, uint256 cap) {
        DegenDriver fund2_ = s_fund2;
        if (address(fund2_) == address(0)) {
            revert CruiseControl__Fund2NotSet();
        }
        fund1Value = _value();
        fund2Value = fund2_.value();
        cap = _amountToMove(i_fund1Usdc, fund1Value, i_fund2Usdc, fund2Value);
    }

    /// @notice Returns the stored Fund 2.
    /// @return fund2_ Fund 2. The zero address means {setFund2} has not been called.
    function fund2() external view returns (DegenDriver fund2_) {
        fund2_ = s_fund2;
    }
}
