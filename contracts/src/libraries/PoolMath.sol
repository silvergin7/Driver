// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOfficialPool} from "../interfaces/IOfficialPool.sol";

/// @title Pool math
/// @notice Constant-product quotes for the official pool.
/// @dev Trader output is floored. Trader input is ceiled. USDC tax is ceiled. Tax does not enter the reserves.
library PoolMath {
    /// @notice Denominator for a tax rate in basis points.
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Amounts and reserves after one quote.
    struct Result {
        uint256 amountIn;
        uint256 amountOut;
        uint256 usdcTax;
        uint256 newReserveDvr;
        uint256 newReserveUsdc;
    }

    /// @notice Quotes a fixed input.
    /// @dev Buy tax is ceiled out of the mUSDC input. Sell tax is ceiled out of the mUSDC the curve emits.
    /// @param direction Buy or sell.
    /// @param reserveDvr Stored DVR reserve, in base units.
    /// @param reserveUsdc Stored mUSDC reserve, in base units.
    /// @param amountIn Asset the trader pays, in base units.
    /// @param taxBps Tax in basis points.
    /// @return result Quote. `amountOut` is DVR on a buy and post-tax mUSDC on a sell.
    function quoteExactInput(
        IOfficialPool.Direction direction,
        uint256 reserveDvr,
        uint256 reserveUsdc,
        uint256 amountIn,
        uint256 taxBps
    ) internal pure returns (Result memory result) {
        if (amountIn == 0) {
            revert IOfficialPool.OfficialPool__ZeroAmount();
        }
        if (reserveDvr == 0 || reserveUsdc == 0) {
            revert IOfficialPool.OfficialPool__InsufficientReserves();
        }

        result.amountIn = amountIn;
        if (direction == IOfficialPool.Direction.Buy) {
            result.usdcTax = Math.mulDiv(amountIn, taxBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
            uint256 usdcToReserve = amountIn - result.usdcTax;
            if (usdcToReserve == 0) {
                revert IOfficialPool.OfficialPool__ZeroAmount();
            }
            result.amountOut = Math.mulDiv(reserveDvr, usdcToReserve, reserveUsdc + usdcToReserve);
            if (result.amountOut == 0) {
                revert IOfficialPool.OfficialPool__ZeroOutput();
            }
            if (result.amountOut >= reserveDvr) {
                revert IOfficialPool.OfficialPool__InsufficientReserves();
            }
            result.newReserveDvr = reserveDvr - result.amountOut;
            result.newReserveUsdc = reserveUsdc + usdcToReserve;
        } else {
            uint256 usdcGross = Math.mulDiv(reserveUsdc, amountIn, reserveDvr + amountIn);
            if (usdcGross == 0) {
                revert IOfficialPool.OfficialPool__ZeroOutput();
            }
            if (usdcGross >= reserveUsdc) {
                revert IOfficialPool.OfficialPool__InsufficientReserves();
            }
            result.usdcTax = Math.mulDiv(usdcGross, taxBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
            result.amountOut = usdcGross - result.usdcTax;
            if (result.amountOut == 0) {
                revert IOfficialPool.OfficialPool__ZeroOutput();
            }
            result.newReserveDvr = reserveDvr + amountIn;
            result.newReserveUsdc = reserveUsdc - usdcGross;
        }
    }

    /// @notice Quotes a fixed output.
    /// @dev The trader receives `amountOut` exactly. Buy input is the ceiled mUSDC that leaves the post-tax
    /// curve amount. Sell input is the ceiled DVR that pays the pre-tax mUSDC output.
    /// @param direction Buy or sell.
    /// @param reserveDvr Stored DVR reserve, in base units.
    /// @param reserveUsdc Stored mUSDC reserve, in base units.
    /// @param amountOut Asset the trader receives, in base units. DVR on a buy, post-tax mUSDC on a sell.
    /// @param taxBps Tax in basis points.
    /// @return result Quote. `amountIn` is gross mUSDC on a buy and DVR on a sell.
    function quoteExactOutput(
        IOfficialPool.Direction direction,
        uint256 reserveDvr,
        uint256 reserveUsdc,
        uint256 amountOut,
        uint256 taxBps
    ) internal pure returns (Result memory result) {
        if (amountOut == 0) {
            revert IOfficialPool.OfficialPool__ZeroAmount();
        }
        if (reserveDvr == 0 || reserveUsdc == 0) {
            revert IOfficialPool.OfficialPool__InsufficientReserves();
        }

        result.amountOut = amountOut;
        if (direction == IOfficialPool.Direction.Buy) {
            if (amountOut >= reserveDvr) {
                revert IOfficialPool.OfficialPool__InsufficientReserves();
            }
            uint256 usdcToReserve = Math.mulDiv(reserveUsdc, amountOut, reserveDvr - amountOut, Math.Rounding.Ceil);
            result.amountIn = Math.mulDiv(usdcToReserve, BPS_DENOMINATOR, BPS_DENOMINATOR - taxBps, Math.Rounding.Ceil);
            result.usdcTax = result.amountIn - usdcToReserve;
            result.newReserveDvr = reserveDvr - amountOut;
            result.newReserveUsdc = reserveUsdc + usdcToReserve;
        } else {
            result.usdcTax = Math.mulDiv(amountOut, taxBps, BPS_DENOMINATOR - taxBps, Math.Rounding.Ceil);
            uint256 usdcGross = amountOut + result.usdcTax;
            if (usdcGross >= reserveUsdc) {
                revert IOfficialPool.OfficialPool__InsufficientReserves();
            }
            result.amountIn = Math.mulDiv(reserveDvr, usdcGross, reserveUsdc - usdcGross, Math.Rounding.Ceil);
            if (result.amountIn == 0) {
                revert IOfficialPool.OfficialPool__ZeroAmount();
            }
            result.newReserveDvr = reserveDvr + result.amountIn;
            result.newReserveUsdc = reserveUsdc - usdcGross;
        }
    }
}
