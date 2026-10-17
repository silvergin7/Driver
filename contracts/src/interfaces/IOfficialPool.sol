// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DriverToken} from "../DriverToken.sol";
import {MockUSDC} from "../MockUSDC.sol";

/// @title Official pool
/// @notice Swap surface for the DVR/mUSDC pool. A later pool can replace the implementation behind this.
interface IOfficialPool {
    /// @notice Which asset the trader pays.
    enum Direction {
        /// @notice Trader pays mUSDC and receives DVR.
        Buy,
        /// @notice Trader pays DVR and receives mUSDC.
        Sell
    }

    /// @notice Emitted when a swap settles.
    /// @param trader Account that called the swap.
    /// @param direction Buy or sell.
    /// @param amountIn Asset the trader paid, in base units. mUSDC on a buy, DVR on a sell.
    /// @param amountOut Asset the trader received, in base units. DVR on a buy, post-tax mUSDC on a sell.
    /// @param usdcTax mUSDC taken as tax, in base units.
    event Swapped(address indexed trader, Direction direction, uint256 amountIn, uint256 amountOut, uint256 usdcTax);

    /// @notice The input amount was zero, or a buy left nothing to swap after tax.
    error OfficialPool__ZeroAmount();

    /// @notice The trader's output rounded to zero.
    error OfficialPool__ZeroOutput();

    /// @notice The pool has no liquidity, or the trade would spend an entire side.
    error OfficialPool__InsufficientReserves();

    /// @notice The output is below the trader's minimum.
    /// @param amountOut Output the swap would have paid, in base units.
    /// @param minAmountOut Minimum the trader required, in base units.
    error OfficialPool__InsufficientOutput(uint256 amountOut, uint256 minAmountOut);

    /// @notice The input is above the trader's maximum.
    /// @param amountIn Input the swap would have taken, in base units.
    /// @param maxAmountIn Maximum the trader allowed, in base units.
    error OfficialPool__ExcessiveInput(uint256 amountIn, uint256 maxAmountIn);

    /// @notice The deadline is before `block.timestamp`.
    /// @param deadline Timestamp the trader required.
    /// @param timestamp `block.timestamp` at the call.
    error OfficialPool__DeadlinePassed(uint256 deadline, uint256 timestamp);

    /// @notice Swaps a fixed input for as much output as the curve and the tax allow.
    /// @dev Reverts with {OfficialPool__DeadlinePassed} when `block.timestamp` is after `deadline`.
    /// A deadline equal to `block.timestamp` is accepted. The deadline uses `block.timestamp`.
    /// @param direction Buy or sell.
    /// @param amountIn Asset to pay, in base units. Must be greater than zero.
    /// @param minAmountOut Minimum asset to receive, in base units.
    /// @param deadline Last accepted `block.timestamp`, inclusive.
    /// @return amountOut Asset received, in base units.
    function swapExactInput(Direction direction, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external
        returns (uint256 amountOut);

    /// @notice Swaps for a fixed output, taking at most `maxAmountIn`.
    /// @dev Reverts with {OfficialPool__DeadlinePassed} when `block.timestamp` is after `deadline`.
    /// A deadline equal to `block.timestamp` is accepted. The deadline uses `block.timestamp`.
    /// @param direction Buy or sell.
    /// @param amountOut Asset to receive, in base units. Must be greater than zero.
    /// @param maxAmountIn Maximum asset to pay, in base units.
    /// @param deadline Last accepted `block.timestamp`, inclusive.
    /// @return amountIn Asset paid, in base units.
    function swapExactOutput(Direction direction, uint256 amountOut, uint256 maxAmountIn, uint256 deadline)
        external
        returns (uint256 amountIn);

    /// @notice Quotes a fixed input at the current reserves and tax.
    /// @param direction Buy or sell.
    /// @param amountIn Asset the trader would pay, in base units.
    /// @return amountOut Asset the trader would receive, in base units.
    /// @return usdcTax mUSDC tax, in base units.
    function quoteExactInput(Direction direction, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, uint256 usdcTax);

    /// @notice Returns the DVR token traded by this pool.
    /// @return dvr_ DVR token.
    function i_dvr() external view returns (DriverToken dvr_);

    /// @notice Returns the Mock USDC traded by this pool.
    /// @return usdc_ Mock USDC.
    function i_usdc() external view returns (MockUSDC usdc_);

    /// @notice Returns the stored DVR reserve.
    /// @return reserveDvr_ DVR counted by the curve, in base units.
    function reserveDvr() external view returns (uint256 reserveDvr_);

    /// @notice Returns the stored mUSDC reserve.
    /// @return reserveUsdc_ mUSDC counted by the curve, in base units.
    function reserveUsdc() external view returns (uint256 reserveUsdc_);

    /// @notice Returns the tax rate.
    /// @return taxBps_ Tax in basis points. 10_000 is 100 percent.
    function taxBps() external view returns (uint256 taxBps_);
}
