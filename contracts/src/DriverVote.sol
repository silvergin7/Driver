// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {ITreasuryFund} from "./interfaces/ITreasuryFund.sol";
import {DriverToken} from "./DriverToken.sol";
import {RoundSchedule} from "./RoundSchedule.sol";
import {TaxSplitter} from "./TaxSplitter.sol";

/// @title Driver vote
/// @notice Locks DVR and records Fund 2's ballot. One locked base unit is one unit of weight.
/// @dev Locks persist across rounds. A vote does not. Round N+1 starts empty, and the holder must vote
/// again. This contract has no owner and no function that sends DVR to an address argument. DVR sent here
/// directly is not a lock and cannot be withdrawn. {DriverToken} transfers the exact amount, so {lock}
/// accounts that amount and does not read the token balance. The open round is {RoundSchedule.currentRound}.
/// A round is open from its start inclusive until its end exclusive. At the end timestamp the next round
/// is already open.
contract DriverVote is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice DVR this ballot locks.
    DriverToken public immutable i_token;

    /// @notice Schedule whose open round this ballot reads.
    RoundSchedule public immutable i_schedule;

    /// @notice Fund 2. Votes are farms on this fund's list.
    ITreasuryFund public immutable i_fund;

    /// @notice Sum of {s_locked}. Direct transfers are not included.
    uint256 private s_counted;

    /// @notice DVR pulled by {lock} and not yet returned.
    mapping(address holder => uint256 amount) private s_locked;

    /// @notice Farm a holder chose in a round. The zero address means they have not voted in that round.
    mapping(uint256 roundId => mapping(address holder => address farm)) private s_vote;

    /// @notice Weight recorded for a farm in a round, in DVR base units.
    mapping(uint256 roundId => mapping(address farm => uint256 weight)) private s_tally;

    /// @notice Emitted when a holder locks DVR.
    /// @param holder Account that locked.
    /// @param amount DVR pulled, in base units.
    /// @param locked That holder's lock after this call, in base units.
    event Locked(address indexed holder, uint256 amount, uint256 locked);

    /// @notice Emitted when a holder unlocks DVR.
    /// @param holder Account that unlocked.
    /// @param amount DVR returned, in base units.
    /// @param locked That holder's lock after this call, in base units.
    event Unlocked(address indexed holder, uint256 amount, uint256 locked);

    /// @notice Emitted when a holder votes in the open round.
    /// @param holder Account that voted.
    /// @param roundId Open round the vote is stored in.
    /// @param farm Farm the holder chose.
    /// @param weight Lock weight counted for `farm` after this vote, in DVR base units.
    event VoteCast(address indexed holder, uint256 indexed roundId, address indexed farm, uint256 weight);

    /// @notice An address argument was zero.
    error DriverVote__ZeroAddress();

    /// @notice The amount was zero.
    error DriverVote__ZeroAmount();

    /// @notice The fund does not read this schedule.
    error DriverVote__ScheduleMismatch();

    /// @notice The fund is not Fund 2.
    error DriverVote__NotFund2();

    /// @notice The holder does not have that much locked.
    /// @param locked Holder's lock, in DVR base units.
    /// @param amount Amount the holder tried to unlock, in DVR base units.
    error DriverVote__InsufficientLock(uint256 locked, uint256 amount);

    /// @notice The holder has no DVR locked.
    error DriverVote__NothingLocked();

    /// @notice The farm is not on Fund 2's list.
    /// @param farm Account that was rejected.
    error DriverVote__StrategyNotAllowed(address farm);

    /// @notice The holder voted in the open round.
    /// @param roundId Open round.
    /// @param unlocksAt First clock time at which that round is closed.
    error DriverVote__Voted(uint256 roundId, uint256 unlocksAt);

    /// @notice Stores the token, the schedule, and Fund 2.
    /// @dev Reverts with {DriverVote__ZeroAddress} when an argument is zero, with
    /// {DriverVote__ScheduleMismatch} when `fund` reads a different schedule, and with
    /// {DriverVote__NotFund2} when `fund` is not Fund 2. There is no owner.
    /// @param token DVR this ballot locks. The zero address is rejected.
    /// @param schedule Schedule whose open round this ballot reads. The zero address is rejected.
    /// @param fund Fund 2. The zero address is rejected.
    constructor(DriverToken token, RoundSchedule schedule, ITreasuryFund fund) {
        if (address(token) == address(0) || address(schedule) == address(0) || address(fund) == address(0)) {
            revert DriverVote__ZeroAddress();
        }
        if (address(fund.i_schedule()) != address(schedule)) {
            revert DriverVote__ScheduleMismatch();
        }
        if (fund.i_fundId() != TaxSplitter.FundId.Fund2) {
            revert DriverVote__NotFund2();
        }
        i_token = token;
        i_schedule = schedule;
        i_fund = fund;
    }

    /// @notice Pulls `amount` DVR from the caller and adds it to the caller's lock.
    /// @dev Reverts with {DriverVote__ZeroAmount} when `amount` is zero. The token reverts when the caller
    /// has not approved this contract or does not hold `amount`. A lock in the open round adds `amount` to
    /// the farm the caller already chose in that round. It does not change an earlier round. The counted
    /// total increases by `amount`, which is the amount pulled. Only the caller may lock for the caller.
    /// @param amount DVR to lock, in base units. Must be greater than zero.
    function lock(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert DriverVote__ZeroAmount();
        }
        uint256 roundId = i_schedule.currentRound();
        uint256 nextLocked = s_locked[msg.sender] + amount;
        s_locked[msg.sender] = nextLocked;
        s_counted += amount;
        address farm = s_vote[roundId][msg.sender];
        if (farm != address(0)) {
            s_tally[roundId][farm] += amount;
        }
        IERC20(i_token).safeTransferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, nextLocked);
    }

    /// @notice Returns `amount` of the caller's lock.
    /// @dev Reverts with {DriverVote__ZeroAmount} when `amount` is zero, with {DriverVote__Voted} when the
    /// caller has a vote in the open round, and with {DriverVote__InsufficientLock} when `amount` is above
    /// the caller's lock. A vote in an earlier round does not block this call. At the open round's end
    /// timestamp the next round is open, so a vote in the round that just closed no longer blocks. This
    /// call does not change a tally. DVR is sent to the caller only.
    /// @param amount DVR to unlock, in base units. Must be greater than zero and at most the caller's lock.
    function unlock(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert DriverVote__ZeroAmount();
        }
        uint256 roundId = i_schedule.currentRound();
        if (s_vote[roundId][msg.sender] != address(0)) {
            revert DriverVote__Voted(roundId, i_schedule.roundEnd(roundId));
        }
        uint256 locked_ = s_locked[msg.sender];
        if (amount > locked_) {
            revert DriverVote__InsufficientLock(locked_, amount);
        }
        uint256 nextLocked = locked_ - amount;
        s_locked[msg.sender] = nextLocked;
        s_counted -= amount;
        IERC20(i_token).safeTransfer(msg.sender, amount);
        emit Unlocked(msg.sender, amount, nextLocked);
    }

    /// @notice Stores the caller's farm for the open round and counts the caller's lock as its weight.
    /// @dev Reverts with {DriverVote__ZeroAddress} when `farm` is zero, with {DriverVote__StrategyNotAllowed}
    /// when `farm` is not on Fund 2's list, and with {DriverVote__NothingLocked} when the caller has no lock.
    /// A later vote in the same round replaces the earlier one. The previous farm, including one de-listed
    /// since the vote, loses this caller's current lock, and `farm` gains it. Voting for the same farm leaves
    /// the tally unchanged. An extra lock after this call increases that weight. A later round starts empty.
    /// @param farm Listed Fund 2 farm. The zero address is rejected.
    function vote(IMockFarm farm) external nonReentrant {
        if (address(farm) == address(0)) {
            revert DriverVote__ZeroAddress();
        }
        if (!i_fund.isStrategy(address(farm))) {
            revert DriverVote__StrategyNotAllowed(address(farm));
        }
        uint256 roundId = i_schedule.currentRound();
        uint256 weight = s_locked[msg.sender];
        if (weight == 0) {
            revert DriverVote__NothingLocked();
        }
        address previous = s_vote[roundId][msg.sender];
        if (previous != address(farm)) {
            if (previous != address(0)) {
                s_tally[roundId][previous] -= weight;
            }
            s_tally[roundId][address(farm)] += weight;
            s_vote[roundId][msg.sender] = address(farm);
        }
        emit VoteCast(msg.sender, roundId, address(farm), weight);
    }

    /// @notice Returns `holder`'s lock.
    /// @param holder Account to query.
    /// @return locked_ DVR still locked, in base units.
    function locked(address holder) external view returns (uint256 locked_) {
        locked_ = s_locked[holder];
    }

    /// @notice Returns the sum of every lock.
    /// @dev Direct transfers are not included. The token balance can be larger than this.
    /// @return counted_ Sum of locks, in DVR base units.
    function counted() external view returns (uint256 counted_) {
        counted_ = s_counted;
    }

    /// @notice Returns the farm `holder` chose in `roundId`.
    /// @param roundId Round to query, starting at zero.
    /// @param holder Account to query.
    /// @return farm_ Chosen farm. The zero address means `holder` has not voted in that round.
    function voteOf(uint256 roundId, address holder) external view returns (address farm_) {
        farm_ = s_vote[roundId][holder];
    }

    /// @notice Returns the weight stored for `farm` in `roundId`.
    /// @param roundId Round to query, starting at zero.
    /// @param farm Farm to query.
    /// @return weight_ Stored weight, in DVR base units. Zero when `farm` has no weight in that round.
    function tally(uint256 roundId, address farm) external view returns (uint256 weight_) {
        weight_ = s_tally[roundId][farm];
    }

    /// @notice Returns the weight stored for `farm` in the open round.
    /// @param farm Farm to query.
    /// @return weight_ Stored weight, in DVR base units.
    function openTally(address farm) external view returns (uint256 weight_) {
        weight_ = s_tally[i_schedule.currentRound()][farm];
    }

    /// @notice Returns whether `holder` can unlock now, and the clock time that answer uses.
    /// @dev A zero lock cannot unlock. A vote in the open round cannot unlock until that round's end.
    /// Any other positive lock can unlock at the clock's current time, including at the exact end of a
    /// round the holder voted in.
    /// @param holder Account to query.
    /// @return canUnlock True when `holder` has a lock and has not voted in the open round.
    /// @return unlocksAt The open round's end when a vote blocks the unlock, the clock's current time when
    /// the holder can unlock now, or zero when the holder has no lock.
    function unlockStatus(address holder) external view returns (bool canUnlock, uint256 unlocksAt) {
        uint256 locked_ = s_locked[holder];
        if (locked_ == 0) {
            return (false, 0);
        }
        uint256 roundId = i_schedule.currentRound();
        if (s_vote[roundId][holder] != address(0)) {
            return (false, i_schedule.roundEnd(roundId));
        }
        return (true, i_schedule.i_clock().currentTime());
    }

    /// @notice Returns the clock time at which the open round ends.
    /// @return end_ End timestamp. The next round is open at this same time.
    function openRoundEnd() external view returns (uint256 end_) {
        end_ = i_schedule.roundEnd(i_schedule.currentRound());
    }
}
