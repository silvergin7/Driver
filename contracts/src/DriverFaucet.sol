// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DriverToken} from "./DriverToken.sol";

/// @title DVR faucet
/// @notice Public faucet that pays a fixed amount of DVR from its own balance.
/// @dev Claim size, cooldown, and the daily cap are fixed at construction. There is no owner, no refill,
/// and no withdraw. {claim} uses `block.timestamp` and pays with `SafeERC20`. A stored claim time of zero
/// means that account has never claimed. State is updated before the transfer. `nonReentrant` guards that call.
contract DriverFaucet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Token this faucet pays from its own balance.
    DriverToken public immutable i_token;

    /// @notice Amount paid by one claim, in base units.
    uint256 public immutable i_claimAmount;

    /// @notice Minimum time between two claims by the same account.
    uint256 public immutable i_claimCooldown;

    /// @notice Maximum claims across all accounts in one UTC day.
    uint256 public immutable i_dailyClaimLimit;

    mapping(address account => uint256 claimedAt) private s_lastClaimAt;
    uint256 private s_claimsToday;
    uint256 private s_trackedDay;

    /// @notice Emitted when an account claims tokens.
    /// @param account Account that received the claim.
    /// @param amount Amount transferred, in base units.
    event Claimed(address indexed account, uint256 amount);

    /// @notice The token address was zero.
    error DriverFaucet__ZeroAddress();

    /// @notice A claim parameter was zero.
    error DriverFaucet__ZeroValue();

    /// @notice The account is still inside its claim cooldown.
    /// @param nextClaimAt Timestamp at which the account may claim again.
    error DriverFaucet__ClaimTooSoon(uint256 nextClaimAt);

    /// @notice This UTC day has already reached the claim cap.
    /// @param nextDailyReset Timestamp at which the daily count resets.
    error DriverFaucet__DailyLimitReached(uint256 nextDailyReset);

    /// @notice The faucet balance cannot cover one claim.
    /// @param balance Faucet balance at the time of the claim, in base units.
    /// @param claimAmount Amount one claim would transfer, in base units.
    error DriverFaucet__InsufficientBalance(uint256 balance, uint256 claimAmount);

    /// @notice Stores the token and the fixed claim parameters.
    /// @param token DVR token to transfer. The zero address is rejected.
    /// @param claimAmount Amount of one claim, in base units. Zero is rejected.
    /// @param claimCooldown Minimum time between claims by the same account. Zero is rejected.
    /// @param dailyClaimLimit Maximum claims across all accounts in one UTC day. Zero is rejected.
    constructor(DriverToken token, uint256 claimAmount, uint256 claimCooldown, uint256 dailyClaimLimit) {
        if (address(token) == address(0)) {
            revert DriverFaucet__ZeroAddress();
        }
        if (claimAmount == 0 || claimCooldown == 0 || dailyClaimLimit == 0) {
            revert DriverFaucet__ZeroValue();
        }
        i_token = token;
        i_claimAmount = claimAmount;
        i_claimCooldown = claimCooldown;
        i_dailyClaimLimit = dailyClaimLimit;
    }

    /// @notice Transfers one claim to the caller when the daily cap, the cooldown, and the balance allow it.
    /// @dev Reverts with {DriverFaucet__DailyLimitReached} when this UTC day is full. Reverts with
    /// {DriverFaucet__ClaimTooSoon} only when `s_lastClaimAt` is non-zero and `block.timestamp` is still
    /// before that time plus the cooldown. Reverts with {DriverFaucet__InsufficientBalance} when the faucet
    /// balance is below one claim. A zero claim time is never claimed, so the first claim succeeds at
    /// Foundry's starting timestamp of 1. Checks run in that order, then the claim count and timestamp are
    /// stored, then `safeTransfer` pays from this contract's balance.
    function claim() external nonReentrant {
        uint256 dayStart = _dayStart(block.timestamp);
        if (s_trackedDay != dayStart) {
            s_trackedDay = dayStart;
            s_claimsToday = 0;
        }
        if (s_claimsToday >= i_dailyClaimLimit) {
            revert DriverFaucet__DailyLimitReached(dayStart + 1 days);
        }

        uint256 lastClaimAt = s_lastClaimAt[msg.sender];
        if (lastClaimAt != 0 && block.timestamp < lastClaimAt + i_claimCooldown) {
            revert DriverFaucet__ClaimTooSoon(lastClaimAt + i_claimCooldown);
        }

        uint256 balance = i_token.balanceOf(address(this));
        if (balance < i_claimAmount) {
            revert DriverFaucet__InsufficientBalance(balance, i_claimAmount);
        }

        s_claimsToday += 1;
        s_lastClaimAt[msg.sender] = block.timestamp;

        IERC20(i_token).safeTransfer(msg.sender, i_claimAmount);
        emit Claimed(msg.sender, i_claimAmount);
    }

    /// @notice Returns the timestamp at which `account` may claim again.
    /// @param account Account to query.
    /// @return nextClaimAt_ Zero when `account` has never claimed. Otherwise the last claim plus the cooldown.
    function nextClaimAt(address account) public view returns (uint256 nextClaimAt_) {
        uint256 lastClaimAt = s_lastClaimAt[account];
        if (lastClaimAt == 0) {
            return 0;
        }
        nextClaimAt_ = lastClaimAt + i_claimCooldown;
    }

    /// @notice Returns how many claims have succeeded in the current UTC day.
    /// @return claimsToday_ Zero when the stored day is not today's UTC day.
    function claimsToday() public view returns (uint256 claimsToday_) {
        if (s_trackedDay != _dayStart(block.timestamp)) {
            return 0;
        }
        claimsToday_ = s_claimsToday;
    }

    /// @notice Returns the next UTC midnight.
    /// @return nextDailyReset_ Timestamp at which the daily claim count resets.
    function nextDailyReset() public view returns (uint256 nextDailyReset_) {
        nextDailyReset_ = _dayStart(block.timestamp) + 1 days;
    }

    /// @dev Truncates `timestamp` to the UTC midnight that begins its day.
    function _dayStart(uint256 timestamp) internal pure returns (uint256 dayStart) {
        dayStart = (timestamp / 1 days) * 1 days;
    }
}
