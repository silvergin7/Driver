// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDriverClock} from "./interfaces/IDriverClock.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {IOfficialPool} from "./interfaces/IOfficialPool.sol";
import {ITreasuryFund} from "./interfaces/ITreasuryFund.sol";
import {MockFarm} from "./MockFarm.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {RoundSchedule} from "./RoundSchedule.sol";
import {TaxSplitter} from "./TaxSplitter.sol";

/// @title Treasury fund
/// @notice Shared accounting for Cruise Control and Degen Driver.
/// @dev Idle mUSDC and claimed farm rewards are separate ledgers. Value is idle plus principal on the active
/// farm. mUSDC sent here directly is not credited and cannot be deployed. The constructor farm list is the
/// only list. No function sends mUSDC to a wallet or to an address argument. {emergencyWithdraw} returns the
/// active farm's principal to this contract and removes that farm from the list.
abstract contract TreasuryFund is ITreasuryFund, ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @inheritdoc ITreasuryFund
    MockUSDC public immutable i_usdc;

    /// @inheritdoc ITreasuryFund
    IDriverClock public immutable i_clock;

    /// @inheritdoc ITreasuryFund
    RoundSchedule public immutable i_schedule;

    /// @inheritdoc ITreasuryFund
    TaxSplitter public immutable i_taxSplitter;

    /// @inheritdoc ITreasuryFund
    IOfficialPool public immutable i_pool;

    /// @inheritdoc ITreasuryFund
    TaxSplitter.FundId public immutable i_fundId;

    /// @inheritdoc ITreasuryFund
    uint256 public immutable i_fund1Usdc;

    /// @inheritdoc ITreasuryFund
    uint256 public immutable i_fund2Usdc;

    /// @notice mUSDC pulled by {supply} and not yet deposited.
    uint256 private s_idle;

    /// @notice Farm rewards {claim} has already paid, waiting for a later harvest.
    uint256 private s_heldRewards;

    /// @notice Farm that holds this fund's principal. Zero until the first switch.
    IMockFarm private s_activeFarm;

    mapping(address farm => bool allowed) private s_allowed;
    IMockFarm[] private s_farms;

    /// @notice True after the first harvest. Round 0 is a real id, so zero storage cannot mark it.
    bool private s_hasHarvested;

    /// @notice Latest round this fund has harvested.
    uint256 private s_lastHarvestedRound;

    /// @notice mUSDC a buyback skipped because the pool would take nothing or return nothing.
    uint256 private s_pendingBuyback;

    /// @notice DVR this fund has bought and burned.
    uint256 private s_dvrBoughtBack;

    /// @notice Amounts from the latest harvest.
    Harvest private s_lastHarvest;

    /// @notice Farm removed by the latest emergency exit. Zero when there has not been one.
    address private s_lastExitStrategy;

    /// @notice Principal returned by the latest emergency exit, in base units.
    uint256 private s_lastExitAmount;

    /// @notice Reason supplied for the latest emergency exit. It is empty when there has not been one.
    string private s_lastExitReason;

    /// @notice Emitted when the owner pulls mUSDC into this fund.
    /// @param from Account that paid.
    /// @param amount mUSDC pulled, in base units.
    /// @param idle Idle balance after the pull, in base units.
    event CapitalSupplied(address indexed from, uint256 amount, uint256 idle);

    /// @notice Emitted when idle mUSDC is deposited into the active farm.
    /// @param farm Farm that received the deposit.
    /// @param amount mUSDC deposited, in base units.
    /// @param idle Idle balance after the deposit, in base units.
    event CapitalDeployed(address indexed farm, uint256 amount, uint256 idle);

    /// @notice Emitted when the constructor lists a farm.
    /// @param farm Farm added to the list.
    event StrategyListed(address indexed farm);

    /// @notice Emitted when the active farm changes.
    /// @param previousFarm Farm that was active. The zero address means there was none.
    /// @param newFarm Farm that is active now.
    /// @param principalMoved Principal moved from `previousFarm` to `newFarm`, in base units.
    /// @param rewardsClaimed Amount {IMockFarm.claim} returned, in base units.
    event StrategySet(
        address indexed previousFarm, address indexed newFarm, uint256 principalMoved, uint256 rewardsClaimed
    );

    /// @notice Emitted when a closed round is harvested.
    /// @param roundId Closed round this call applied.
    /// @param taxReleased mUSDC released from this fund's splitter bucket, in base units.
    /// @param rewards Farm rewards taken into this harvest, in base units.
    /// @param compounded Half of `rewards` put back to work, in base units. This half keeps the odd unit.
    /// @param buybackSpent mUSDC swapped for DVR, in base units. Zero when the buyback was skipped.
    /// @param dvrBurned DVR bought and burned, in base units.
    /// @param pendingBuyback mUSDC still waiting for a later buyback, in base units.
    event Harvested(
        uint256 indexed roundId,
        uint256 taxReleased,
        uint256 rewards,
        uint256 compounded,
        uint256 buybackSpent,
        uint256 dvrBurned,
        uint256 pendingBuyback
    );

    /// @notice Emitted when the owner pulls this fund's principal out of the active farm.
    /// @param fund This fund.
    /// @param strategy Farm the principal left.
    /// @param amount Principal returned to this fund, in base units. Zero when that farm held none.
    /// @param reason Reason supplied by the owner.
    event EmergencyWithdrawn(address indexed fund, address indexed strategy, uint256 amount, string reason);

    /// @notice Emitted when a farm is removed from the strategy list.
    /// @param farm Farm removed from the list.
    event StrategyDelisted(address indexed farm);

    /// @notice An address argument was zero.
    error TreasuryFund__ZeroAddress();

    /// @notice The amount was zero.
    error TreasuryFund__ZeroAmount();

    /// @notice Fund 1's starting share was not strictly larger than Fund 2's.
    /// @param fund1Usdc Fund 1's share, in mUSDC base units.
    /// @param fund2Usdc Fund 2's share, in mUSDC base units.
    error TreasuryFund__Fund1ShareNotLarger(uint256 fund1Usdc, uint256 fund2Usdc);

    /// @notice The constructor farm list was empty.
    error TreasuryFund__NoFarms();

    /// @notice No farm is active.
    error TreasuryFund__NoActiveFarm();

    /// @notice The fund does not have that much idle mUSDC.
    /// @param idle Idle balance, in base units.
    /// @param amount Amount the caller tried to deposit, in base units.
    error TreasuryFund__InsufficientIdle(uint256 idle, uint256 amount);

    /// @notice That farm was not in the constructor list.
    /// @param farm Account that was rejected.
    error TreasuryFund__StrategyNotAllowed(address farm);

    /// @notice That farm was already in the constructor list.
    /// @param farm Account that was repeated.
    error TreasuryFund__StrategyAlreadyListed(address farm);

    /// @notice That farm is already the active farm.
    /// @param farm Farm that is already active.
    error TreasuryFund__StrategyUnchanged(address farm);

    /// @notice That farm's token is not this fund's mUSDC.
    /// @param farm Farm that was rejected.
    error TreasuryFund__FarmTokenMismatch(address farm);

    /// @notice That farm's clock is not this fund's clock.
    /// @param farm Farm that was rejected.
    error TreasuryFund__FarmClockMismatch(address farm);

    /// @notice The splitter's pool is not `pool`, or that pool's token is not this fund's mUSDC.
    /// @param pool Account that was rejected.
    error TreasuryFund__PoolMismatch(address pool);

    /// @notice That schedule does not read this fund's clock.
    /// @param schedule Schedule that was rejected.
    error TreasuryFund__ScheduleClockMismatch(address schedule);

    /// @notice That closed round was already harvested, or an older round was requested after a newer one.
    /// @param roundId Closed round the call tried to apply.
    error TreasuryFund__RoundAlreadyHarvested(uint256 roundId);

    /// @notice The pool's buy quote failed for a reason other than a zero input or a zero output.
    error TreasuryFund__BuybackQuoteRejected();

    /// @notice The emergency-exit reason was an empty string.
    error TreasuryFund__EmptyReason();

    /// @notice The farm returned a different principal from the amount read before the call.
    /// @param expected Principal read from the farm before the call, in base units.
    /// @param returned Amount {IMockFarm.emergencyWithdraw} returned, in base units.
    error TreasuryFund__PrincipalMismatch(uint256 expected, uint256 returned);

    /// @notice Stores the token, the clock, the schedule, the splitter, the pool, the bucket, and the farm list.
    /// @dev Reverts with {TreasuryFund__ZeroAddress} when `usdc`, `clock`, `schedule`, `taxSplitter`, or `pool`
    /// is zero. Reverts with {TreasuryFund__ZeroAmount} when `fund1Usdc` or `fund2Usdc` is zero, and with
    /// {TreasuryFund__Fund1ShareNotLarger} when `fund1Usdc` is not strictly larger than `fund2Usdc`. Reverts
    /// with {TreasuryFund__PoolMismatch} unless the splitter's pool is `pool` and that pool's mUSDC is `usdc`.
    /// Reverts with {TreasuryFund__ScheduleClockMismatch} unless the schedule reads `clock`. A zero owner
    /// reverts in {Ownable}. The farm list is checked by {_listFarms}. A zero `fundId` is not possible: the
    /// child passes {TaxSplitter.FundId}.
    /// @param usdc Mock USDC this fund holds. The zero address is rejected.
    /// @param clock Clock this fund and its farms read. The zero address is rejected.
    /// @param schedule Shared round schedule. The zero address is rejected.
    /// @param taxSplitter Splitter whose bucket this fund will release. The zero address is rejected.
    /// @param pool Official pool stored for a later buyback. The zero address is rejected.
    /// @param fundId Splitter bucket. Cruise Control passes Fund 1. Degen Driver passes Fund 2.
    /// @param fund1Usdc Fund 1's starting share, in mUSDC base units. Zero is rejected, and it must be
    /// strictly larger than `fund2Usdc`.
    /// @param fund2Usdc Fund 2's starting share, in mUSDC base units. Zero is rejected.
    /// @param farms Farms this fund may use. The list must be non-empty, and each entry must be non-zero,
    /// unique, and use `usdc` and `clock`.
    /// @param initialOwner Account allowed to supply and deposit. The zero address is rejected.
    constructor(
        MockUSDC usdc,
        IDriverClock clock,
        RoundSchedule schedule,
        TaxSplitter taxSplitter,
        IOfficialPool pool,
        TaxSplitter.FundId fundId,
        uint256 fund1Usdc,
        uint256 fund2Usdc,
        IMockFarm[] memory farms,
        address initialOwner
    ) Ownable(initialOwner) {
        if (
            address(usdc) == address(0) || address(clock) == address(0) || address(schedule) == address(0)
                || address(taxSplitter) == address(0) || address(pool) == address(0)
        ) {
            revert TreasuryFund__ZeroAddress();
        }
        if (fund1Usdc == 0 || fund2Usdc == 0) {
            revert TreasuryFund__ZeroAmount();
        }
        if (fund1Usdc <= fund2Usdc) {
            revert TreasuryFund__Fund1ShareNotLarger(fund1Usdc, fund2Usdc);
        }
        if (taxSplitter.pool() != address(pool) || address(pool.i_usdc()) != address(usdc)) {
            revert TreasuryFund__PoolMismatch(address(pool));
        }
        if (address(schedule.i_clock()) != address(clock)) {
            revert TreasuryFund__ScheduleClockMismatch(address(schedule));
        }
        i_usdc = usdc;
        i_clock = clock;
        i_schedule = schedule;
        i_taxSplitter = taxSplitter;
        i_pool = pool;
        i_fundId = fundId;
        i_fund1Usdc = fund1Usdc;
        i_fund2Usdc = fund2Usdc;
        _listFarms(farms);
    }

    /// @notice Pulls `amount` of mUSDC from the caller into the idle balance.
    /// @dev Reverts with {TreasuryFund__ZeroAmount} when `amount` is zero. The idle balance is increased
    /// before `safeTransferFrom` pulls from `msg.sender`. Only the owner may call this.
    /// @param amount mUSDC to pull, in base units. Must be greater than zero.
    function supply(uint256 amount) external nonReentrant onlyOwner {
        if (amount == 0) {
            revert TreasuryFund__ZeroAmount();
        }
        s_idle += amount;
        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), amount);
        emit CapitalSupplied(msg.sender, amount, s_idle);
    }

    /// @notice Deposits `amount` of idle mUSDC into the active farm.
    /// @dev Reverts with {TreasuryFund__ZeroAmount} when `amount` is zero, with {TreasuryFund__NoActiveFarm}
    /// when no farm is active, and with {TreasuryFund__InsufficientIdle} when `amount` exceeds idle. Idle is
    /// decreased before the farm is approved and {IMockFarm.deposit} is called. Only the owner may call this.
    /// @param amount Idle mUSDC to deposit, in base units. Must be greater than zero.
    function deposit(uint256 amount) external nonReentrant onlyOwner {
        if (amount == 0) {
            revert TreasuryFund__ZeroAmount();
        }
        IMockFarm farm = s_activeFarm;
        if (address(farm) == address(0)) {
            revert TreasuryFund__NoActiveFarm();
        }
        uint256 idle_ = s_idle;
        if (amount > idle_) {
            revert TreasuryFund__InsufficientIdle(idle_, amount);
        }
        s_idle = idle_ - amount;
        IERC20(i_usdc).forceApprove(address(farm), amount);
        farm.deposit(amount);
        emit CapitalDeployed(address(farm), amount, s_idle);
    }

    /// @notice Harvests one closed round: releases tax, splits rewards, buys and burns DVR, then deploys idle.
    /// @dev Reverts with {Ownable.OwnableUnauthorizedAccount} when the caller is not the owner, with
    /// {RoundSchedule.RoundSchedule__NoClosedRound} while round 0 is open, and with
    /// {TreasuryFund__RoundAlreadyHarvested} when the latest closed round is already stored. The round and
    /// the idle balance are stored before any token call. Degen Driver reads its ballot here, and reads it
    /// again when the round is applied; a different farm reverts in the child. `minDvrOut` may be zero. It
    /// is passed to the buy only when this harvest's buyback half is non-zero and the quote returns an
    /// output. A half of zero does not quote and does not change the deferred buyback. A quote that reverts
    /// with {IOfficialPool.OfficialPool__ZeroAmount} or {IOfficialPool.OfficialPool__ZeroOutput} puts that
    /// spend back into the deferred buyback and does not read `minDvrOut`.
    /// {IOfficialPool.OfficialPool__InsufficientReserves} from the quote is raised again. Any other quote
    /// revert raises {TreasuryFund__BuybackQuoteRejected}. The buy deadline is `block.timestamp`.
    ///
    /// Order: release this fund's accrued tax, or skip an empty bucket. Add the active farm's
    /// {IMockFarm.claim} return to rewards that were already moved out of storage. That credit follows an
    /// external call, because the amount is the return value. The compound half is deposited into the
    /// active farm. When no farm was active, that half was already added to idle. The buyback half is
    /// swapped and the DVR output is burned. Degen Driver may then switch farm. Idle mUSDC already counted
    /// above is deposited when a farm is active. {_afterHarvest} runs last, before {Harvested}.
    /// @param minDvrOut Minimum DVR the buy must return, in base units.
    function harvest(uint256 minDvrOut) external nonReentrant onlyOwner {
        uint256 roundId = i_schedule.latestClosedRound();
        if (s_hasHarvested && roundId <= s_lastHarvestedRound) {
            revert TreasuryFund__RoundAlreadyHarvested(roundId);
        }
        s_hasHarvested = true;
        s_lastHarvestedRound = roundId;

        uint256 idle_ = s_idle + i_taxSplitter.accrued(i_fundId);
        uint256 taxReleased = idle_ - s_idle;
        uint256 rewards = s_heldRewards;
        s_heldRewards = 0;
        IMockFarm farm = s_activeFarm;
        uint256 buybackHalf = 0;
        uint256 compounded = 0;
        if (address(farm) == address(0)) {
            buybackHalf = rewards / 2;
            compounded = rewards - buybackHalf;
            idle_ += compounded;
        }
        IMockFarm endFarm = _farmAfterRound(roundId);
        uint256 deployAmount = 0;
        if (address(endFarm) == address(0)) {
            s_idle = idle_;
        } else {
            s_idle = 0;
            deployAmount = idle_;
        }

        if (taxReleased != 0) {
            i_taxSplitter.release(i_fundId);
        }
        if (address(farm) != address(0)) {
            rewards += farm.claim();
            buybackHalf = rewards / 2;
            compounded = rewards - buybackHalf;
            if (compounded != 0) {
                _depositAmount(farm, compounded);
                emit CapitalDeployed(address(farm), compounded, s_idle);
            }
        }
        (uint256 buybackSpent, uint256 dvrBurned) = _buyback(buybackHalf, minDvrOut);
        _applyClosedRound(roundId, endFarm);
        if (deployAmount != 0) {
            _depositAmount(s_activeFarm, deployAmount);
            emit CapitalDeployed(address(s_activeFarm), deployAmount, 0);
        }
        _afterHarvest(roundId);

        uint256 pending = s_pendingBuyback;
        s_lastHarvest = Harvest({
            roundId: roundId,
            taxReleased: taxReleased,
            rewards: rewards,
            compounded: compounded,
            buybackSpent: buybackSpent,
            dvrBurned: dvrBurned,
            pendingBuyback: pending
        });
        emit Harvested(roundId, taxReleased, rewards, compounded, buybackSpent, dvrBurned, pending);
    }

    /// @inheritdoc ITreasuryFund
    function emergencyWithdraw(string calldata reason) external nonReentrant onlyOwner {
        _exitActiveFarm(reason);
    }

    /// @inheritdoc ITreasuryFund
    function idle() external view returns (uint256 idle_) {
        idle_ = s_idle;
    }

    /// @inheritdoc ITreasuryFund
    function heldRewards() external view returns (uint256 heldRewards_) {
        heldRewards_ = s_heldRewards;
    }

    /// @inheritdoc ITreasuryFund
    function activeFarm() external view returns (IMockFarm farm_) {
        farm_ = s_activeFarm;
    }

    /// @inheritdoc ITreasuryFund
    function principal() external view returns (uint256 principal_) {
        principal_ = _principal();
    }

    /// @inheritdoc ITreasuryFund
    function value() external view returns (uint256 value_) {
        value_ = _value();
    }

    /// @inheritdoc ITreasuryFund
    function pendingRewards() external view returns (uint256 rewards_) {
        IMockFarm farm = s_activeFarm;
        if (address(farm) == address(0)) {
            return 0;
        }
        rewards_ = farm.accrued(address(this));
    }

    /// @inheritdoc ITreasuryFund
    function harvestableRound() external view returns (bool ready_, uint256 roundId_) {
        uint256 openRound = i_schedule.currentRound();
        if (openRound == 0 || (s_hasHarvested && s_lastHarvestedRound >= openRound - 1)) {
            return (false, openRound);
        }
        ready_ = true;
        roundId_ = openRound - 1;
    }

    /// @inheritdoc ITreasuryFund
    function lastHarvestedRound() external view returns (bool harvested_, uint256 roundId_) {
        harvested_ = s_hasHarvested;
        roundId_ = s_lastHarvestedRound;
    }

    /// @inheritdoc ITreasuryFund
    function dvrBoughtBack() external view returns (uint256 burned_) {
        burned_ = s_dvrBoughtBack;
    }

    /// @inheritdoc ITreasuryFund
    function pendingBuyback() external view returns (uint256 pending_) {
        pending_ = s_pendingBuyback;
    }

    /// @inheritdoc ITreasuryFund
    function lastHarvest() external view returns (Harvest memory harvest_) {
        harvest_ = s_lastHarvest;
    }

    /// @inheritdoc ITreasuryFund
    function isStrategy(address farm) external view returns (bool allowed_) {
        allowed_ = s_allowed[farm];
    }

    /// @inheritdoc ITreasuryFund
    function strategyCount() external view returns (uint256 count_) {
        count_ = s_farms.length;
    }

    /// @inheritdoc ITreasuryFund
    function strategyAt(uint256 index) external view returns (IMockFarm farm_) {
        farm_ = s_farms[index];
    }

    /// @inheritdoc ITreasuryFund
    function lastEmergencyExit() external view returns (address strategy, uint256 amount, string memory reason) {
        strategy = s_lastExitStrategy;
        amount = s_lastExitAmount;
        reason = s_lastExitReason;
    }

    /// @notice Moves principal to `newFarm` and stores rewards the outgoing farm actually paid.
    /// @dev The caller must be `nonReentrant`. {CruiseControl.setStrategy} is. A later harvest that calls
    /// this must be `nonReentrant` itself and must not rely on a second guard here: {ReentrancyGuard} does
    /// not nest. `newFarm` was listed in the constructor.
    ///
    /// Order: reject a zero, unlisted, or already active farm. Store `newFarm` as the active farm before any
    /// farm call. When there is no outgoing farm, emit zeros and return. Otherwise read that farm's
    /// principal, call {IMockFarm.claim}, and add the returned amount to `s_heldRewards`. That credit is
    /// the one step that follows an external call, because the amount is the return value and is not taken
    /// from a view. When the principal is non-zero, withdraw it from the outgoing farm and deposit it into
    /// `newFarm`. Idle mUSDC is left idle.
    /// @param newFarm Listed farm that becomes active. The zero address is rejected.
    function _switchFarm(IMockFarm newFarm) internal {
        if (address(newFarm) == address(0)) {
            revert TreasuryFund__ZeroAddress();
        }
        if (!s_allowed[address(newFarm)]) {
            revert TreasuryFund__StrategyNotAllowed(address(newFarm));
        }
        IMockFarm previous = s_activeFarm;
        if (address(previous) == address(newFarm)) {
            revert TreasuryFund__StrategyUnchanged(address(newFarm));
        }

        s_activeFarm = newFarm;
        if (address(previous) == address(0)) {
            emit StrategySet(address(0), address(newFarm), 0, 0);
            return;
        }

        uint256 principalMoved = previous.principalOf(address(this));
        uint256 rewardsClaimed = previous.claim();
        s_heldRewards += rewardsClaimed;
        if (principalMoved != 0) {
            previous.withdraw(principalMoved);
            IERC20(i_usdc).forceApprove(address(newFarm), principalMoved);
            newFarm.deposit(principalMoved);
        }

        emit StrategySet(address(previous), address(newFarm), principalMoved, rewardsClaimed);
    }

    /// @dev `reason` is memory so a later caller can pass a string literal. The external caller is
    /// `nonReentrant`. This function has no guard of its own, because the guard does not nest.
    ///
    /// Order: reject an empty reason, then no active farm. Read that farm's principal before any write, then
    /// whether it is already paused. Clear the active farm, remove it from the list, add the principal to
    /// idle, and store the exit. When the principal is not zero, call {IMockFarm.emergencyWithdraw}. That
    /// call does not read the clock and does not claim. A different return reverts
    /// {TreasuryFund__PrincipalMismatch} and rolls the exit back. When the farm was not already paused,
    /// pause it. {EmergencyWithdrawn} follows those calls.
    /// @param reason Reason stored and emitted. An empty string is rejected.
    function _exitActiveFarm(string memory reason) internal {
        if (bytes(reason).length == 0) {
            revert TreasuryFund__EmptyReason();
        }
        IMockFarm farm = s_activeFarm;
        if (address(farm) == address(0)) {
            revert TreasuryFund__NoActiveFarm();
        }
        uint256 amount = farm.principalOf(address(this));
        bool alreadyPaused = farm.paused();

        s_activeFarm = IMockFarm(address(0));
        _delist(farm);
        s_idle += amount;
        s_lastExitStrategy = address(farm);
        s_lastExitAmount = amount;
        s_lastExitReason = reason;

        if (amount != 0) {
            uint256 returned = farm.emergencyWithdraw();
            if (returned != amount) {
                revert TreasuryFund__PrincipalMismatch(amount, returned);
            }
        }
        if (!alreadyPaused) {
            farm.pause();
        }
        emit EmergencyWithdrawn(address(this), address(farm), amount, reason);
    }

    /// @dev Clears the allow-list flag and shifts later entries down, so the remaining order is the original
    /// registration order. Reverts with {TreasuryFund__StrategyNotAllowed} when `farm` is not in the list.
    /// @param farm Farm to remove.
    function _delist(IMockFarm farm) internal {
        address farmAddress = address(farm);
        uint256 count = s_farms.length;
        for (uint256 i = 0; i < count; i++) {
            if (address(s_farms[i]) != farmAddress) {
                continue;
            }
            s_allowed[farmAddress] = false;
            for (uint256 j = i; j + 1 < count; j++) {
                s_farms[j] = s_farms[j + 1];
            }
            s_farms.pop();
            emit StrategyDelisted(farmAddress);
            return;
        }
        revert TreasuryFund__StrategyNotAllowed(farmAddress);
    }

    /// @dev Reverts with {TreasuryFund__NoFarms} when `farms` is empty. Each entry reverts with
    /// {TreasuryFund__ZeroAddress}, {TreasuryFund__StrategyAlreadyListed}, {TreasuryFund__FarmTokenMismatch},
    /// or {TreasuryFund__FarmClockMismatch}. A listed farm is stored before the next entry is checked.
    function _listFarms(IMockFarm[] memory farms) internal {
        if (farms.length == 0) {
            revert TreasuryFund__NoFarms();
        }
        uint256 count = farms.length;
        for (uint256 i = 0; i < count; i++) {
            IMockFarm farm = farms[i];
            if (address(farm) == address(0)) {
                revert TreasuryFund__ZeroAddress();
            }
            if (s_allowed[address(farm)]) {
                revert TreasuryFund__StrategyAlreadyListed(address(farm));
            }
            if (address(MockFarm(address(farm)).i_usdc()) != address(i_usdc)) {
                revert TreasuryFund__FarmTokenMismatch(address(farm));
            }
            if (address(MockFarm(address(farm)).i_clock()) != address(i_clock)) {
                revert TreasuryFund__FarmClockMismatch(address(farm));
            }
            s_allowed[address(farm)] = true;
            s_farms.push(farm);
            emit StrategyListed(address(farm));
        }
    }

    /// @dev Returns principal on the active farm, or zero when no farm is active.
    function _principal() internal view returns (uint256 principal_) {
        IMockFarm farm = s_activeFarm;
        if (address(farm) == address(0)) {
            return 0;
        }
        principal_ = farm.principalOf(address(this));
    }

    /// @dev Swaps `half` plus any deferred buyback for DVR and burns the output. A zero half does nothing.
    /// @return spent_ mUSDC swapped. Zero when the buy was skipped.
    /// @return burned_ DVR burned. Zero when the buy was skipped.
    function _buyback(uint256 half, uint256 minDvrOut) private returns (uint256 spent_, uint256 burned_) {
        if (half == 0) {
            return (0, 0);
        }
        uint256 spend = half + s_pendingBuyback;
        s_pendingBuyback = 0;
        if (_quoteDefers(spend)) {
            s_pendingBuyback = spend;
            return (0, 0);
        }
        IERC20(i_usdc).forceApprove(address(i_pool), spend);
        burned_ = i_pool.swapExactInput(IOfficialPool.Direction.Buy, spend, minDvrOut, block.timestamp);
        IERC20(i_usdc).forceApprove(address(i_pool), 0);
        i_pool.i_dvr().burn(burned_);
        s_dvrBoughtBack += burned_;
        spent_ = spend;
    }

    /// @dev Deposits `amount` into `farm` and clears that approval. `amount` is greater than zero.
    function _depositAmount(IMockFarm farm, uint256 amount) private {
        IERC20(i_usdc).forceApprove(address(farm), amount);
        farm.deposit(amount);
        IERC20(i_usdc).forceApprove(address(farm), 0);
    }

    /// @dev Returns the farm that will be active once `roundId` is applied. Fund 1 returns the current farm.
    function _farmAfterRound(uint256) internal view virtual returns (IMockFarm farm_) {
        farm_ = s_activeFarm;
    }

    /// @dev Fund 2 applies `expectedFarm` here. Fund 1 does not. `expectedFarm` is the farm {_farmAfterRound} returned.
    function _applyClosedRound(uint256, IMockFarm) internal virtual {}

    /// @dev Degen Driver rebalances here, after idle has been deployed, inside this harvest.
    function _afterHarvest(uint256) internal virtual {}

    /// @dev Returns idle plus principal on the active farm.
    function _value() internal view returns (uint256 value_) {
        value_ = s_idle + _principal();
    }

    /// @dev Reduces idle by up to `amount` and returns how much of `amount` idle covered.
    function _takeFromIdle(uint256 amount) internal returns (uint256 taken) {
        uint256 idle_ = s_idle;
        taken = idle_ < amount ? idle_ : amount;
        if (taken != 0) {
            s_idle = idle_ - taken;
        }
    }

    /// @dev Floor of the mUSDC `payerValue` must send so the two values match `payerShare` and `receiverShare`.
    /// Returns zero when the receiver is already at or above its share. The subtraction runs only after that
    /// comparison, so it cannot underflow.
    function _amountToMove(uint256 payerShare, uint256 payerValue, uint256 receiverShare, uint256 receiverValue)
        internal
        pure
        returns (uint256 amount)
    {
        uint256 owed = receiverShare * payerValue;
        uint256 held = payerShare * receiverValue;
        if (owed <= held) {
            return 0;
        }
        amount = (owed - held) / (payerShare + receiverShare);
    }

    /// @dev Credits idle, or fixes the deposit amount, before pulling `amount` and depositing it.
    function _acceptCapital(uint256 amount) internal {
        if (amount == 0) {
            revert TreasuryFund__ZeroAmount();
        }
        IMockFarm farm = s_activeFarm;
        if (address(farm) == address(0)) {
            s_idle += amount;
            IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), amount);
            emit CapitalSupplied(msg.sender, amount, s_idle);
            return;
        }
        uint256 depositAmount = amount;
        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), amount);
        _depositAmount(farm, depositAmount);
        emit CapitalDeployed(address(farm), depositAmount, s_idle);
    }

    /// @dev Returns the active farm. The zero address means no farm has been selected.
    function _activeFarm() internal view returns (IMockFarm farm_) {
        farm_ = s_activeFarm;
    }

    /// @dev Returns true when a buy of `spend` should be deferred. Other quote reverts propagate.
    function _quoteDefers(uint256 spend) private view returns (bool) {
        try i_pool.quoteExactInput(IOfficialPool.Direction.Buy, spend) returns (uint256 amountOut, uint256 usdcTax) {
            if (amountOut == 0 || usdcTax > spend) {
                return true;
            }
            return false;
        } catch (bytes memory reason) {
            bytes32 reasonHash = keccak256(reason);
            if (
                reasonHash == keccak256(abi.encodeWithSelector(IOfficialPool.OfficialPool__ZeroAmount.selector))
                    || reasonHash == keccak256(abi.encodeWithSelector(IOfficialPool.OfficialPool__ZeroOutput.selector))
            ) {
                return true;
            }
            if (
                reasonHash
                    == keccak256(abi.encodeWithSelector(IOfficialPool.OfficialPool__InsufficientReserves.selector))
            ) {
                revert IOfficialPool.OfficialPool__InsufficientReserves();
            }
            revert TreasuryFund__BuybackQuoteRejected();
        }
    }
}
