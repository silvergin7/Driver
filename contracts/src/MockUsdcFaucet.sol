// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MockUSDC} from "./MockUSDC.sol";

/// @title Mock USDC faucet
/// @notice Public faucet that mints a fixed amount of Mock USDC.
/// @dev Claim size, cooldown, and the daily cap are fixed at construction. There is no owner and no
/// refill. {claim} uses `block.timestamp`. A stored claim time of zero means that account has never
/// claimed. State is updated before the mint. `nonReentrant` guards that external call.
contract MockUsdcFaucet is ReentrancyGuard {
    /// @notice Token this faucet mints.
    MockUSDC public immutable i_usdc;

    /// @notice Amount minted by one claim, in base units.
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
    /// @param amount Amount minted, in base units.
    event Claimed(address indexed account, uint256 amount);

    /// @notice The token address was zero.
    error MockUsdcFaucet__ZeroAddress();

    /// @notice A claim parameter was zero.
    error MockUsdcFaucet__ZeroValue();

    /// @notice The account is still inside its claim cooldown.
    /// @param nextClaimAt Timestamp at which the account may claim again.
    error MockUsdcFaucet__ClaimTooSoon(uint256 nextClaimAt);

    /// @notice This UTC day has already reached the claim cap.
    /// @param nextDailyReset Timestamp at which the daily count resets.
    error MockUsdcFaucet__DailyLimitReached(uint256 nextDailyReset);

    /// @notice Stores the token and the fixed claim parameters.
    /// @param usdc Mock USDC token to mint. The zero address is rejected.
    /// @param claimAmount Amount of one claim, in base units. Zero is rejected.
    /// @param claimCooldown Minimum time between claims by the same account. Zero is rejected.
    /// @param dailyClaimLimit Maximum claims across all accounts in one UTC day. Zero is rejected.
    constructor(MockUSDC usdc, uint256 claimAmount, uint256 claimCooldown, uint256 dailyClaimLimit) {
        if (address(usdc) == address(0)) {
            revert MockUsdcFaucet__ZeroAddress();
        }
        if (claimAmount == 0 || claimCooldown == 0 || dailyClaimLimit == 0) {
            revert MockUsdcFaucet__ZeroValue();
        }
        i_usdc = usdc;
        i_claimAmount = claimAmount;
        i_claimCooldown = claimCooldown;
        i_dailyClaimLimit = dailyClaimLimit;
    }

    /// @notice Mints one claim to the caller when the cooldown and the daily cap allow it.
    /// @dev Reverts with {MockUsdcFaucet__DailyLimitReached} when this UTC day is full. Reverts with
    /// {MockUsdcFaucet__ClaimTooSoon} only when `s_lastClaimAt` is non-zero and `block.timestamp` is
    /// still before that time plus the cooldown. A zero claim time is never claimed, so the first
    /// claim succeeds at Foundry's starting timestamp of 1.
    function claim() external nonReentrant {
        uint256 dayStart = _dayStart(block.timestamp);
        if (s_trackedDay != dayStart) {
            s_trackedDay = dayStart;
            s_claimsToday = 0;
        }
        if (s_claimsToday >= i_dailyClaimLimit) {
            revert MockUsdcFaucet__DailyLimitReached(dayStart + 1 days);
        }

        uint256 lastClaimAt = s_lastClaimAt[msg.sender];
        if (lastClaimAt != 0 && block.timestamp < lastClaimAt + i_claimCooldown) {
            revert MockUsdcFaucet__ClaimTooSoon(lastClaimAt + i_claimCooldown);
        }

        s_claimsToday += 1;
        s_lastClaimAt[msg.sender] = block.timestamp;

        i_usdc.mintFromFaucet(msg.sender, i_claimAmount);
        emit Claimed(msg.sender, i_claimAmount);
    }

    /// @notice Returns the timestamp at which `account` may claim again.
    /// @param account Account to query.
    /// @return nextClaimAt_ Zero when `account` has never claimed. Otherwise the last claim plus the cooldown.
    function nextClaimAt(address account) public view returns (uint256 nextClaimAt_) {
        uint256 lastClaimAt = s_lastClaimAt[account];
        // Zero is the never-claimed sentinel.
        // slither-disable-next-line incorrect-equality
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
        // Floors to UTC midnight on purpose.
        // slither-disable-next-line divide-before-multiply
        dayStart = (timestamp / 1 days) * 1 days;
    }
}
