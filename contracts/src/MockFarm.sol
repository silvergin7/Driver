// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDriverClock} from "./interfaces/IDriverClock.sol";
import {IMockFarm} from "./interfaces/IMockFarm.sol";
import {MockUSDC} from "./MockUSDC.sol";

/// @title Mock farm
/// @notice Linear mUSDC farm. Rewards come from a pre-funded reserve and principal is tracked per account.
/// @dev Time comes from {IDriverClock.currentTime}. This contract does not read `block.timestamp`. Reward
/// math rounds down. Principal and the reward reserve are separate ledgers. mUSDC sent here directly is not
/// credited to either ledger. A depositor can pause the farm. Deposit, withdraw, claim, funding, and new
/// depositors then stop. {emergencyWithdraw} does not.
contract MockFarm is IMockFarm, ReentrancyGuard, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Denominator for {i_aprBps}. 10_000 is 100 percent.
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Seconds in the year used by the reward formula.
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Mock USDC deposited and paid as rewards.
    MockUSDC public immutable i_usdc;

    /// @notice Clock that supplies the accrual time.
    IDriverClock public immutable i_clock;

    /// @notice APR in basis points. Fixed for the life of the farm.
    uint256 public immutable i_aprBps;

    mapping(address account => bool allowed) private s_isDepositor;
    mapping(address account => uint256 amount) private s_principal;
    mapping(address account => uint256 amount) private s_accrued;
    mapping(address account => uint64 timestamp) private s_lastAccrual;
    uint256 private s_totalPrincipal;
    uint256 private s_rewardReserve;

    /// @notice Emitted when the owner adds a depositor.
    /// @param depositor Account that may deposit, withdraw, and claim.
    event DepositorAdded(address indexed depositor);

    /// @notice Emitted when a depositor adds principal.
    /// @param account Account that deposited.
    /// @param amount mUSDC deposited, in base units.
    /// @param principal That account's principal after the deposit, in base units.
    event Deposited(address indexed account, uint256 amount, uint256 principal);

    /// @notice Emitted when a depositor removes principal.
    /// @param account Account that withdrew.
    /// @param amount mUSDC returned, in base units.
    /// @param principal That account's principal after the withdrawal, in base units.
    event Withdrawn(address indexed account, uint256 amount, uint256 principal);

    /// @notice Emitted when the owner adds mUSDC to the reward reserve.
    /// @param funder Account that funded the reserve.
    /// @param amount mUSDC added, in base units.
    /// @param rewardReserve Reserve after the funding, in base units.
    event RewardsFunded(address indexed funder, uint256 amount, uint256 rewardReserve);

    /// @notice An address argument was zero.
    error MockFarm__ZeroAddress();

    /// @notice The APR was zero.
    error MockFarm__ZeroApr();

    /// @notice That account is already a depositor.
    /// @param depositor Account that was already added.
    error MockFarm__DepositorAlreadyAdded(address depositor);

    /// @notice The caller is not a depositor.
    modifier onlyDepositor() {
        if (!s_isDepositor[msg.sender]) {
            revert MockFarm__CallerNotDepositor(msg.sender);
        }
        _;
    }

    /// @notice Sets the token, the clock, the APR, and the owner. No depositor is added.
    /// @dev Reverts with {MockFarm__ZeroAddress} when `usdc` or `clock` is zero, and with {MockFarm__ZeroApr}
    /// when `aprBps` is zero. A zero owner reverts in {Ownable}.
    /// @param usdc Mock USDC accounted by this farm. The zero address is rejected.
    /// @param clock Clock later calls read. The zero address is rejected.
    /// @param initialAprBps APR in basis points. Must be greater than zero.
    /// @param initialOwner Account allowed to add depositors and fund rewards. The zero address is rejected.
    constructor(MockUSDC usdc, IDriverClock clock, uint256 initialAprBps, address initialOwner) Ownable(initialOwner) {
        if (address(usdc) == address(0) || address(clock) == address(0)) {
            revert MockFarm__ZeroAddress();
        }
        if (initialAprBps == 0) {
            revert MockFarm__ZeroApr();
        }
        i_usdc = usdc;
        i_clock = clock;
        i_aprBps = initialAprBps;
    }

    /// @inheritdoc IMockFarm
    function deposit(uint256 amount) external nonReentrant onlyDepositor whenNotPaused {
        if (amount == 0) {
            revert MockFarm__ZeroAmount();
        }

        _checkpoint(msg.sender);
        uint256 newPrincipal = s_principal[msg.sender] + amount;
        s_principal[msg.sender] = newPrincipal;
        s_totalPrincipal += amount;
        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount, newPrincipal);
    }

    /// @inheritdoc IMockFarm
    function withdraw(uint256 amount) external nonReentrant onlyDepositor whenNotPaused {
        if (amount == 0) {
            revert MockFarm__ZeroAmount();
        }
        uint256 balance = s_principal[msg.sender];
        if (amount > balance) {
            revert MockFarm__InsufficientPrincipal(balance, amount);
        }

        _checkpoint(msg.sender);
        uint256 newPrincipal = balance - amount;
        s_principal[msg.sender] = newPrincipal;
        s_totalPrincipal -= amount;
        IERC20(i_usdc).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, newPrincipal);
    }

    /// @inheritdoc IMockFarm
    function emergencyWithdraw() external nonReentrant onlyDepositor returns (uint256 principal) {
        principal = s_principal[msg.sender];
        if (principal == 0) {
            revert MockFarm__ZeroAmount();
        }

        uint256 forfeited = s_accrued[msg.sender];
        s_principal[msg.sender] = 0;
        s_totalPrincipal -= principal;
        s_accrued[msg.sender] = 0;
        IERC20(i_usdc).safeTransfer(msg.sender, principal);
        emit EmergencyWithdrawn(msg.sender, principal, forfeited);
    }

    /// @inheritdoc IMockFarm
    function claim() external nonReentrant onlyDepositor whenNotPaused returns (uint256 paid) {
        uint256 owed = _checkpoint(msg.sender);
        if (owed == 0) {
            return 0;
        }

        uint256 reserve = s_rewardReserve;
        paid = owed > reserve ? reserve : owed;
        uint256 unpaid = owed - paid;
        s_accrued[msg.sender] = unpaid;
        s_rewardReserve = reserve - paid;
        if (paid != 0) {
            IERC20(i_usdc).safeTransfer(msg.sender, paid);
        }
        emit RewardsClaimed(msg.sender, paid, unpaid);
    }

    /// @notice Adds an account that may deposit, withdraw, and claim.
    /// @dev Reverts with {MockFarm__ZeroAddress} when `depositor` is zero, and with
    /// {MockFarm__DepositorAlreadyAdded} when that account was already added, and with `EnforcedPause` when
    /// the farm is paused. A depositor cannot be removed.
    /// @param depositor Account to add. The zero address is rejected.
    function addDepositor(address depositor) external nonReentrant onlyOwner whenNotPaused {
        if (depositor == address(0)) {
            revert MockFarm__ZeroAddress();
        }
        if (s_isDepositor[depositor]) {
            revert MockFarm__DepositorAlreadyAdded(depositor);
        }
        s_isDepositor[depositor] = true;
        emit DepositorAdded(depositor);
    }

    /// @notice Moves `amount` of mUSDC from the owner into the reward reserve.
    /// @dev Reverts with {MockFarm__ZeroAmount} when `amount` is zero, and with `EnforcedPause` when the farm
    /// is paused. The reserve is increased before the transfer. Only the owner may call this.
    /// @param amount mUSDC to add, in base units. Must be greater than zero.
    function fundRewards(uint256 amount) external nonReentrant onlyOwner whenNotPaused {
        if (amount == 0) {
            revert MockFarm__ZeroAmount();
        }

        s_rewardReserve += amount;
        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsFunded(msg.sender, amount, s_rewardReserve);
    }

    /// @inheritdoc IMockFarm
    function pause() external nonReentrant onlyDepositor {
        _pause();
    }

    /// @inheritdoc IMockFarm
    function accrued(address account) public view returns (uint256 accrued_) {
        uint256 stored_ = s_accrued[account];
        uint256 principal = s_principal[account];
        if (principal == 0) {
            return stored_;
        }

        uint256 nowTime = i_clock.currentTime();
        uint256 last = s_lastAccrual[account];
        if (nowTime <= last) {
            return stored_;
        }
        accrued_ = stored_ + _earned(principal, nowTime - last);
    }

    /// @inheritdoc IMockFarm
    function principalOf(address account) external view returns (uint256 principal_) {
        principal_ = s_principal[account];
    }

    /// @inheritdoc IMockFarm
    function totalPrincipal() external view returns (uint256 totalPrincipal_) {
        totalPrincipal_ = s_totalPrincipal;
    }

    /// @inheritdoc IMockFarm
    function rewardReserve() external view returns (uint256 rewardReserve_) {
        rewardReserve_ = s_rewardReserve;
    }

    /// @inheritdoc IMockFarm
    function aprBps() external view returns (uint256 aprBps_) {
        aprBps_ = i_aprBps;
    }

    /// @inheritdoc IMockFarm
    function isDepositor(address account) external view returns (bool isDepositor_) {
        isDepositor_ = s_isDepositor[account];
    }

    /// @inheritdoc IMockFarm
    function paused() public view override(IMockFarm, Pausable) returns (bool paused_) {
        paused_ = super.paused();
    }

    /// @dev Stores pending rewards for `account` and moves its checkpoint to {IDriverClock.currentTime}.
    /// A zero principal stores nothing. A clock time before the checkpoint underflows when principal is
    /// non-zero, so {deposit}, {withdraw}, and {claim} revert. The token transfer is not done here.
    function _checkpoint(address account) internal returns (uint256 stored_) {
        uint256 nowTime = i_clock.currentTime();
        uint256 principal = s_principal[account];
        stored_ = s_accrued[account];
        if (principal != 0) {
            uint256 elapsed = nowTime - s_lastAccrual[account];
            if (elapsed != 0) {
                uint256 earned = _earned(principal, elapsed);
                if (earned != 0) {
                    stored_ += earned;
                    s_accrued[account] = stored_;
                }
            }
        }
        s_lastAccrual[account] = SafeCast.toUint64(nowTime);
    }

    /// @dev Floors `principal * apr * elapsed / (BPS_DENOMINATOR * SECONDS_PER_YEAR)`.
    function _earned(uint256 principal, uint256 elapsed) internal view returns (uint256 earned_) {
        earned_ = Math.mulDiv(principal, i_aprBps * elapsed, BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }
}
