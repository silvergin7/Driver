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
import {TaxSplitter} from "./TaxSplitter.sol";

/// @title Treasury fund
/// @notice Shared accounting for Cruise Control and Degen Driver.
/// @dev Idle mUSDC and claimed farm rewards are separate ledgers. Value is idle plus principal on the active
/// farm. mUSDC sent here directly is not credited and cannot be deployed. The constructor farm list is the
/// only list. No function sends mUSDC to a wallet or to an address argument.
abstract contract TreasuryFund is ITreasuryFund, ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @inheritdoc ITreasuryFund
    MockUSDC public immutable i_usdc;

    /// @inheritdoc ITreasuryFund
    IDriverClock public immutable i_clock;

    /// @inheritdoc ITreasuryFund
    TaxSplitter public immutable i_taxSplitter;

    /// @inheritdoc ITreasuryFund
    IOfficialPool public immutable i_pool;

    /// @inheritdoc ITreasuryFund
    TaxSplitter.FundId public immutable i_fundId;

    /// @notice mUSDC pulled by {supply} and not yet deposited.
    uint256 private s_idle;

    /// @notice Farm rewards {claim} has already paid, waiting for a later harvest.
    uint256 private s_heldRewards;

    /// @notice Farm that holds this fund's principal. Zero until the first switch.
    IMockFarm private s_activeFarm;

    mapping(address farm => bool allowed) private s_allowed;
    IMockFarm[] private s_farms;

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

    /// @notice An address argument was zero.
    error TreasuryFund__ZeroAddress();

    /// @notice The amount was zero.
    error TreasuryFund__ZeroAmount();

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

    /// @notice Stores the token, the clock, the splitter, the pool, the bucket, and the farm list.
    /// @dev Reverts with {TreasuryFund__ZeroAddress} when `usdc`, `clock`, `taxSplitter`, or `pool` is zero.
    /// A zero owner reverts in {Ownable}. The farm list is checked by {_listFarms}. A zero `fundId` is not
    /// possible: the child passes {TaxSplitter.FundId}.
    /// @param usdc Mock USDC this fund holds. The zero address is rejected.
    /// @param clock Clock stored for a later harvest. The zero address is rejected.
    /// @param taxSplitter Splitter whose bucket this fund will release. The zero address is rejected.
    /// @param pool Official pool stored for a later buyback. The zero address is rejected.
    /// @param fundId Splitter bucket. Cruise Control passes Fund 1. Degen Driver passes Fund 2.
    /// @param farms Farms this fund may use. The list must be non-empty, and each entry must be non-zero,
    /// unique, and use `usdc` and `clock`.
    /// @param initialOwner Account allowed to supply and deposit. The zero address is rejected.
    constructor(
        MockUSDC usdc,
        IDriverClock clock,
        TaxSplitter taxSplitter,
        IOfficialPool pool,
        TaxSplitter.FundId fundId,
        IMockFarm[] memory farms,
        address initialOwner
    ) Ownable(initialOwner) {
        if (
            address(usdc) == address(0) || address(clock) == address(0) || address(taxSplitter) == address(0)
                || address(pool) == address(0)
        ) {
            revert TreasuryFund__ZeroAddress();
        }
        i_usdc = usdc;
        i_clock = clock;
        i_taxSplitter = taxSplitter;
        i_pool = pool;
        i_fundId = fundId;
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
        value_ = s_idle + _principal();
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
}
