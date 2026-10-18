// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDriverClock} from "./interfaces/IDriverClock.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {IOfficialPool} from "./interfaces/IOfficialPool.sol";
import {IStrategyBallot} from "./interfaces/IStrategyBallot.sol";
import {CruiseControl} from "./CruiseControl.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {RoundSchedule} from "./RoundSchedule.sol";
import {TaxSplitter} from "./TaxSplitter.sol";
import {TreasuryFund} from "./TreasuryFund.sol";

/// @title Degen Driver
/// @notice Fund 2. Its active farm stays unset until a harvest applies a vote.
/// @dev This contract does not expose a strategy setter. {harvest} calls {_switchFarm} with the closed
/// round's farm when that farm is still listed. A winner that is not listed keeps the current farm, and
/// {WinnerIgnored} is emitted. The ballot is set once. Voting reads the constructor list and does not
/// switch the farm. The splitter bucket is Fund 2.
contract DegenDriver is TreasuryFund {
    using SafeERC20 for IERC20;

    /// @notice One rebalance, including a move of zero.
    struct Rebalance {
        uint256 roundId;
        uint256 fund1Value;
        uint256 fund2Value;
        uint256 amount;
    }

    /// @notice Fund 1. Set at construction and never replaced.
    CruiseControl public immutable i_fund1;

    /// @notice Ballot whose closed-round farm {harvest} applies.
    IStrategyBallot private s_ballot;

    /// @notice True after the first rebalance. Round 0 is a real id, so zero storage cannot mark it.
    bool private s_hasRebalanced;

    /// @notice Latest rebalance, including a move of zero.
    Rebalance private s_lastRebalance;

    /// @notice Emitted when the owner sets the ballot.
    /// @param ballot Ballot stored for later harvests.
    event BallotSet(address indexed ballot);

    /// @notice Emitted when a harvest checks the starting ratio.
    /// @param roundId Closed round the harvest applied.
    /// @param fund1Value Fund 1's value before any move, in mUSDC base units.
    /// @param fund2Value Fund 2's value before any move, in mUSDC base units.
    /// @param amount mUSDC moved from Fund 2 to Fund 1, in base units. Zero when Fund 1 was already at or
    /// above its share, or when the floor of the shortfall is zero.
    event Rebalanced(uint256 indexed roundId, uint256 fund1Value, uint256 fund2Value, uint256 amount);

    /// @notice Emitted when a closed round names a farm that is not on this fund's list.
    /// @param roundId Closed round the harvest applied.
    /// @param winner Farm the ballot returned. It was not listed, so the current farm stayed.
    event WinnerIgnored(uint256 indexed roundId, address indexed winner);

    /// @notice An address argument was zero.
    error DegenDriver__ZeroAddress();

    /// @notice The ballot was already set.
    error DegenDriver__BallotAlreadySet();

    /// @notice The caller is not Fund 1.
    /// @param caller Account that called the function.
    error DegenDriver__NotFund1(address caller);

    /// @notice The ballot's farm changed between the two reads in one harvest.
    /// @param expected Farm read before the token calls.
    /// @param actual Farm read when the round was applied.
    error DegenDriver__WinnerChanged(address expected, address actual);

    /// @notice Stores Fund 2's addresses and its farm list.
    /// @dev Reverts with {DegenDriver__ZeroAddress} when `fund1` is zero. The shared-token, clock, schedule,
    /// and share checks run in {CruiseControl.setFund2}.
    /// @param usdc Mock USDC this fund holds. The zero address is rejected.
    /// @param clock Clock this fund and its farms read. The zero address is rejected.
    /// @param schedule Shared round schedule. The zero address is rejected.
    /// @param taxSplitter Splitter whose Fund 2 bucket this fund will release. The zero address is rejected.
    /// @param pool Official pool stored for a later buyback. The zero address is rejected.
    /// @param fund1 Fund 1. The zero address is rejected.
    /// @param fund1Usdc Fund 1's starting share, in mUSDC base units. Zero is rejected, and it must be
    /// strictly larger than `fund2Usdc`.
    /// @param fund2Usdc Fund 2's starting share, in mUSDC base units. Zero is rejected.
    /// @param farms Farms a later harvest may select. The deploy passes Highway, Autobahn, and Drift.
    /// @param initialOwner Account allowed to supply and deposit. The zero address is rejected.
    constructor(
        MockUSDC usdc,
        IDriverClock clock,
        RoundSchedule schedule,
        TaxSplitter taxSplitter,
        IOfficialPool pool,
        CruiseControl fund1,
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
            TaxSplitter.FundId.Fund2,
            fund1Usdc,
            fund2Usdc,
            farms,
            initialOwner
        )
    {
        if (address(fund1) == address(0)) {
            revert DegenDriver__ZeroAddress();
        }
        i_fund1 = fund1;
    }

    /// @notice Stores the ballot harvest reads. A second call reverts.
    /// @dev Reverts with {DegenDriver__ZeroAddress} when `ballot_` is zero, and with
    /// {DegenDriver__BallotAlreadySet} when a ballot is already stored. Only the owner may call this.
    /// This function does not call the ballot or move tokens.
    /// @param ballot_ Ballot for closed rounds. The zero address is rejected.
    function setBallot(IStrategyBallot ballot_) external onlyOwner {
        if (address(ballot_) == address(0)) {
            revert DegenDriver__ZeroAddress();
        }
        if (address(s_ballot) != address(0)) {
            revert DegenDriver__BallotAlreadySet();
        }
        s_ballot = ballot_;
        emit BallotSet(address(ballot_));
    }

    /// @notice Pulls a top-up from Fund 1 and puts it to work.
    /// @dev Reverts with {DegenDriver__NotFund1} when the caller is not Fund 1, and with
    /// {TreasuryFund__ZeroAmount} when `amount` is zero. Idle is credited before the pull when no farm is
    /// active. Otherwise the deposit amount is fixed before the pull and the farm deposit. Only Fund 1 may
    /// call this.
    /// @param amount mUSDC to pull, in base units. Must be greater than zero.
    function acceptTopUp(uint256 amount) external nonReentrant {
        if (msg.sender != address(i_fund1)) {
            revert DegenDriver__NotFund1(msg.sender);
        }
        _acceptCapital(amount);
    }

    /// @notice Returns the move a harvest would make from the current values.
    /// @return fund1Value Fund 1's value, in mUSDC base units.
    /// @return fund2Value Fund 2's value, in mUSDC base units.
    /// @return amount mUSDC that would move, in base units.
    function rebalanceAmount() external view returns (uint256 fund1Value, uint256 fund2Value, uint256 amount) {
        fund1Value = i_fund1.value();
        fund2Value = _value();
        amount = _amountToMove(i_fund2Usdc, fund2Value, i_fund1Usdc, fund1Value);
    }

    /// @notice Returns the ballot harvest reads.
    /// @return ballot_ Stored ballot. The zero address means none was set.
    function ballot() external view returns (IStrategyBallot ballot_) {
        ballot_ = s_ballot;
    }

    /// @notice Returns the latest rebalance.
    /// @dev `executed` is false before the first harvest. Round 0 is a real id, so the bool is the sentinel.
    /// The values are the ones from before the move.
    /// @return executed True after at least one rebalance.
    /// @return roundId Closed round stored by that rebalance.
    /// @return fund1Value Fund 1's value before the move, in mUSDC base units.
    /// @return fund2Value Fund 2's value before the move, in mUSDC base units.
    /// @return amount mUSDC moved, in base units.
    function lastRebalance()
        external
        view
        returns (bool executed, uint256 roundId, uint256 fund1Value, uint256 fund2Value, uint256 amount)
    {
        executed = s_hasRebalanced;
        roundId = s_lastRebalance.roundId;
        fund1Value = s_lastRebalance.fund1Value;
        fund2Value = s_lastRebalance.fund2Value;
        amount = s_lastRebalance.amount;
    }

    /// @dev The ballot is read before {harvest} moves tokens. Address zero, the farm already active, or a farm
    /// that is not listed keeps the current farm.
    function _farmAfterRound(uint256 roundId) internal view override returns (IMockFarm farm_) {
        farm_ = _chosenFarm(roundId);
    }

    /// @dev Reads the ballot again and reverts with {DegenDriver__WinnerChanged} when the farm differs from
    /// `expectedFarm`. A matching new farm goes through {_switchFarm}. A non-zero winner that is not the
    /// active farm and is not listed emits {WinnerIgnored} and leaves the current farm in place. A reverting
    /// {IStrategyBallot.winner} reverts this harvest.
    function _applyClosedRound(uint256 roundId, IMockFarm expectedFarm) internal override {
        IMockFarm chosen_ = _chosenFarm(roundId);
        if (address(chosen_) != address(expectedFarm)) {
            revert DegenDriver__WinnerChanged(address(expectedFarm), address(chosen_));
        }
        address ignored_ = _ignoredWinner(roundId);
        if (address(chosen_) != address(_activeFarm())) {
            _switchFarm(chosen_);
        }
        if (ignored_ != address(0)) {
            emit WinnerIgnored(roundId, ignored_);
        }
    }

    /// @dev Moves mUSDC to Fund 1 when Fund 1 is below its starting share. Idle is debited and the snapshot is
    /// stored before the farm withdraw and the Fund 1 call. The event is emitted after those calls.
    /// A zero move stores and emits without calling Fund 1. Step 5 has already deposited this fund's idle when
    /// a farm is active, so that path withdraws the whole amount.
    function _afterHarvest(uint256 roundId) internal override {
        uint256 fund1Value = i_fund1.value();
        uint256 fund2Value = _value();
        uint256 amount = _amountToMove(i_fund2Usdc, fund2Value, i_fund1Usdc, fund1Value);
        if (amount == 0) {
            _rememberRebalance(roundId, fund1Value, fund2Value, 0);
            emit Rebalanced(roundId, fund1Value, fund2Value, 0);
            return;
        }
        uint256 fromIdle = _takeFromIdle(amount);
        uint256 fromFarm = amount - fromIdle;
        _rememberRebalance(roundId, fund1Value, fund2Value, amount);
        if (fromFarm != 0) {
            _activeFarm().withdraw(fromFarm);
        }
        IERC20(i_usdc).forceApprove(address(i_fund1), amount);
        i_fund1.acceptRebalance(amount);
        IERC20(i_usdc).forceApprove(address(i_fund1), 0);
        emit Rebalanced(roundId, fund1Value, fund2Value, amount);
    }

    /// @dev Stores the pre-move values. Called before any farm or Fund 1 call.
    function _rememberRebalance(uint256 roundId, uint256 fund1Value, uint256 fund2Value, uint256 amount) private {
        s_hasRebalanced = true;
        s_lastRebalance = Rebalance({roundId: roundId, fund1Value: fund1Value, fund2Value: fund2Value, amount: amount});
    }

    /// @dev Address zero, the farm already active, or a farm that is not listed keeps the current farm.
    function _chosenFarm(uint256 roundId) private view returns (IMockFarm farm_) {
        farm_ = _activeFarm();
        IStrategyBallot ballot_ = s_ballot;
        if (address(ballot_) == address(0)) {
            return farm_;
        }
        IMockFarm winner_ = ballot_.winner(roundId);
        if (address(winner_) == address(0) || address(winner_) == address(farm_) || !_isStrategy(address(winner_))) {
            return farm_;
        }
        return winner_;
    }

    /// @dev The raw winner when it must be ignored: non-zero, not the active farm, and not listed. Address zero
    /// means this round does not emit {WinnerIgnored}.
    function _ignoredWinner(uint256 roundId) private view returns (address winner_) {
        IStrategyBallot ballot_ = s_ballot;
        if (address(ballot_) == address(0)) {
            return address(0);
        }
        winner_ = address(ballot_.winner(roundId));
        if (winner_ == address(0) || winner_ == address(_activeFarm()) || _isStrategy(winner_)) {
            return address(0);
        }
    }
}
