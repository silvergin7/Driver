// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Mock farm
/// @notice Deposit, reward, and principal surface for one mock mUSDC farm.
/// @dev Later funds call this interface. Rewards accrue in mUSDC from a separate reserve.
interface IMockFarm {
    /// @notice Emitted when a depositor claims rewards.
    /// @param account Account that claimed.
    /// @param paid mUSDC transferred from the reserve, in base units.
    /// @param unpaid mUSDC still owed after the reserve cap, in base units.
    event RewardsClaimed(address indexed account, uint256 paid, uint256 unpaid);

    /// @notice Emitted when a depositor takes principal without running the reward formula.
    /// @param account Account that withdrew.
    /// @param principal mUSDC returned, in base units.
    /// @param forfeited Stored rewards cleared and left in the reserve, in base units.
    event EmergencyWithdrawn(address indexed account, uint256 principal, uint256 forfeited);

    /// @notice The amount was zero.
    error MockFarm__ZeroAmount();

    /// @notice The caller is not a depositor.
    /// @param caller Account that called the function.
    error MockFarm__CallerNotDepositor(address caller);

    /// @notice The account does not have that much principal.
    /// @param principal Principal of the caller, in base units.
    /// @param amount Amount the caller tried to withdraw, in base units.
    error MockFarm__InsufficientPrincipal(uint256 principal, uint256 amount);

    /// @notice Adds `amount` of mUSDC principal for the caller.
    /// @dev Reverts with {MockFarm__CallerNotDepositor} when the caller is not a depositor, and with
    /// {MockFarm__ZeroAmount} when `amount` is zero. Pending rewards on the existing principal are stored
    /// first. The new amount does not earn for that past time.
    /// @param amount mUSDC to deposit, in base units. Must be greater than zero.
    function deposit(uint256 amount) external;

    /// @notice Stores accrued rewards, then returns `amount` of principal.
    /// @dev Rewards are stored and are not paid or forfeited. The checkpoint uses the principal from before
    /// this call. The token transfer is last. Reverts with {MockFarm__CallerNotDepositor} when the caller
    /// is not a depositor, with {MockFarm__ZeroAmount} when `amount` is zero, and with
    /// {MockFarm__InsufficientPrincipal} when `amount` exceeds principal.
    /// @param amount Principal to return, in base units. Must be greater than zero.
    function withdraw(uint256 amount) external;

    /// @notice Returns the caller's full principal and clears stored rewards.
    /// @dev Does not read the clock and does not run the reward formula. Stored rewards stay in the reserve.
    /// `forfeited` is that stored amount. Unstored rewards are not computed. Reverts with
    /// {MockFarm__CallerNotDepositor} when the caller is not a depositor, and with {MockFarm__ZeroAmount}
    /// when the caller has no principal. A zero principal does not clear stored rewards.
    /// @return principal mUSDC returned, in base units.
    function emergencyWithdraw() external returns (uint256 principal);

    /// @notice Pays stored and pending rewards from the reserve.
    /// @dev A depositor who is owed nothing receives 0 and this does not revert. When the reserve is shorter
    /// than the amount owed, the reserve is paid and the rest stays stored. This does not revert for a short
    /// reserve and does not reduce principal. Reverts with {MockFarm__CallerNotDepositor} for any other caller.
    /// @return paid mUSDC transferred, in base units. Zero when nothing is owed or the reserve is empty.
    function claim() external returns (uint256 paid);

    /// @notice Returns stored rewards plus pending rewards for `account`.
    /// @dev The result is stored plus pending. It is not capped by the reserve. Does not revert when `account`
    /// has no principal or when the reserve is short. Reverts if the clock reverts, or if the reward math
    /// overflows. Pending is zero when `account` has no principal. An account with no principal and no stored
    /// rewards returns zero.
    /// @param account Account to query.
    /// @return accrued_ Stored plus pending mUSDC, in base units.
    function accrued(address account) external view returns (uint256 accrued_);

    /// @notice Returns the principal of `account`.
    /// @param account Account to query.
    /// @return principal_ mUSDC principal, in base units.
    function principalOf(address account) external view returns (uint256 principal_);

    /// @notice Returns the principal of every depositor.
    /// @return totalPrincipal_ Sum of principal, in base units.
    function totalPrincipal() external view returns (uint256 totalPrincipal_);

    /// @notice Returns the mUSDC set aside for rewards.
    /// @return rewardReserve_ Reserve balance tracked for rewards, in base units.
    function rewardReserve() external view returns (uint256 rewardReserve_);

    /// @notice Returns the farm's APR.
    /// @return aprBps_ APR in basis points. 10_000 is 100 percent.
    function aprBps() external view returns (uint256 aprBps_);

    /// @notice Returns whether `account` may deposit, withdraw, and claim.
    /// @param account Account to query.
    /// @return isDepositor_ True when `account` has been added.
    function isDepositor(address account) external view returns (bool isDepositor_);
}
