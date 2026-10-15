// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DriverToken} from "./DriverToken.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {TaxSplitter} from "./TaxSplitter.sol";
import {IOfficialPool} from "./interfaces/IOfficialPool.sol";
import {PoolMath} from "./libraries/PoolMath.sol";

/// @title Official DVR pool
/// @notice Constant-product DVR/mUSDC pool. Swaps take the USDC tax inside the pool.
/// @dev Reserves are stored. Token balances above the reserves are not credited, and there is no withdraw.
/// There is no liquidity-share token and no function that removes liquidity. A swap checks the deadline
/// against `block.timestamp`, writes the new reserves, pulls the input, transfers any tax to the splitter,
/// calls {TaxSplitter.accrue}, then pays the output. This pool does not approve the splitter. A zero tax
/// skips the splitter. The owner and every other trader pay the same tax.
contract OfficialPool is IOfficialPool, ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Hard maximum tax, in basis points.
    uint256 public constant MAX_TAX_BPS = 300;

    /// @notice Denominator for {taxBps}. 10_000 is 100 percent.
    uint256 public constant BPS_DENOMINATOR = PoolMath.BPS_DENOMINATOR;

    /// @notice DVR token traded by this pool.
    DriverToken public immutable i_dvr;

    /// @notice Mock USDC traded by this pool.
    MockUSDC public immutable i_usdc;

    /// @notice Splitter that records the USDC tax.
    TaxSplitter public immutable i_taxSplitter;

    uint256 private s_reserveDvr;
    uint256 private s_reserveUsdc;
    uint256 private s_taxBps;

    /// @notice Emitted when the owner adds liquidity.
    /// @param dvrUsed DVR added to the reserves, in base units.
    /// @param usdcUsed mUSDC added to the reserves, in base units.
    /// @param reserveDvr DVR reserve after the add, in base units.
    /// @param reserveUsdc mUSDC reserve after the add, in base units.
    event LiquidityAdded(uint256 dvrUsed, uint256 usdcUsed, uint256 reserveDvr, uint256 reserveUsdc);

    /// @notice Emitted when the owner changes the tax.
    /// @param previousBps Tax before the change, in basis points.
    /// @param newBps Tax after the change, in basis points.
    event TaxBpsUpdated(uint256 previousBps, uint256 newBps);

    /// @notice An address argument was zero.
    error OfficialPool__ZeroAddress();

    /// @notice The tax was above {MAX_TAX_BPS}.
    /// @param taxBps Requested tax, in basis points.
    /// @param maxTaxBps The hard maximum, in basis points.
    error OfficialPool__TaxAboveMaximum(uint256 taxBps, uint256 maxTaxBps);

    /// @notice Sets the pair, the splitter, the owner, and the starting tax. Reserves start at zero.
    /// @param dvr DVR token. The zero address is rejected.
    /// @param usdc Mock USDC token. The zero address is rejected.
    /// @param taxSplitter Splitter that will record tax. The zero address is rejected.
    /// @param initialOwner Account allowed to add liquidity and set the tax. The zero address is rejected.
    /// @param initialTaxBps Starting tax, in basis points. Zero is accepted. Above {MAX_TAX_BPS} is rejected.
    constructor(DriverToken dvr, MockUSDC usdc, TaxSplitter taxSplitter, address initialOwner, uint256 initialTaxBps)
        Ownable(initialOwner)
    {
        if (address(dvr) == address(0) || address(usdc) == address(0) || address(taxSplitter) == address(0)) {
            revert OfficialPool__ZeroAddress();
        }
        if (initialTaxBps > MAX_TAX_BPS) {
            revert OfficialPool__TaxAboveMaximum(initialTaxBps, MAX_TAX_BPS);
        }
        i_dvr = dvr;
        i_usdc = usdc;
        i_taxSplitter = taxSplitter;
        s_taxBps = initialTaxBps;
    }

    /// @inheritdoc IOfficialPool
    function swapExactInput(Direction direction, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        _revertIfExpired(deadline);
        PoolMath.Result memory result =
            PoolMath.quoteExactInput(direction, s_reserveDvr, s_reserveUsdc, amountIn, s_taxBps);
        if (result.amountOut < minAmountOut) {
            revert OfficialPool__InsufficientOutput(result.amountOut, minAmountOut);
        }
        _settle(direction, result);
        amountOut = result.amountOut;
    }

    /// @inheritdoc IOfficialPool
    function swapExactOutput(Direction direction, uint256 amountOut, uint256 maxAmountIn, uint256 deadline)
        external
        nonReentrant
        returns (uint256 amountIn)
    {
        _revertIfExpired(deadline);
        PoolMath.Result memory result =
            PoolMath.quoteExactOutput(direction, s_reserveDvr, s_reserveUsdc, amountOut, s_taxBps);
        if (result.amountIn > maxAmountIn) {
            revert OfficialPool__ExcessiveInput(result.amountIn, maxAmountIn);
        }
        _settle(direction, result);
        amountIn = result.amountIn;
    }

    /// @notice Adds DVR and mUSDC to the reserves.
    /// @dev Only the owner may call this. There is no remove function. An empty pool takes both amounts and
    /// those amounts set the price. A funded pool takes the largest deposit that matches the current price,
    /// flooring the other side, and leaves the rest with the owner. A floored side of zero reverts.
    /// Reserves are written before the tokens are pulled.
    /// @param dvrAmount DVR offered, in base units. Must be greater than zero.
    /// @param usdcAmount mUSDC offered, in base units. Must be greater than zero.
    /// @return dvrUsed DVR added, in base units.
    /// @return usdcUsed mUSDC added, in base units.
    function addLiquidity(uint256 dvrAmount, uint256 usdcAmount)
        external
        nonReentrant
        onlyOwner
        returns (uint256 dvrUsed, uint256 usdcUsed)
    {
        if (dvrAmount == 0 || usdcAmount == 0) {
            revert OfficialPool__ZeroAmount();
        }

        uint256 dvrReserve = s_reserveDvr;
        uint256 usdcReserve = s_reserveUsdc;
        if (dvrReserve == 0 && usdcReserve == 0) {
            dvrUsed = dvrAmount;
            usdcUsed = usdcAmount;
        } else if (dvrReserve == 0 || usdcReserve == 0) {
            revert OfficialPool__InsufficientReserves();
        } else {
            uint256 usdcOptimal = Math.mulDiv(dvrAmount, usdcReserve, dvrReserve);
            if (usdcOptimal <= usdcAmount) {
                if (usdcOptimal == 0) {
                    revert OfficialPool__ZeroAmount();
                }
                dvrUsed = dvrAmount;
                usdcUsed = usdcOptimal;
            } else {
                uint256 dvrOptimal = Math.mulDiv(usdcAmount, dvrReserve, usdcReserve);
                if (dvrOptimal == 0) {
                    revert OfficialPool__ZeroAmount();
                }
                dvrUsed = dvrOptimal;
                usdcUsed = usdcAmount;
            }
        }

        s_reserveDvr = dvrReserve + dvrUsed;
        s_reserveUsdc = usdcReserve + usdcUsed;
        IERC20(i_dvr).safeTransferFrom(msg.sender, address(this), dvrUsed);
        IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), usdcUsed);
        emit LiquidityAdded(dvrUsed, usdcUsed, s_reserveDvr, s_reserveUsdc);
    }

    /// @notice Sets the tax rate.
    /// @dev Zero is accepted. A value above {MAX_TAX_BPS} reverts and does not write or emit. Setting the
    /// current value is allowed and emits. Only the owner may call this.
    /// @param newTaxBps Tax in basis points.
    function setTaxBps(uint256 newTaxBps) external onlyOwner {
        if (newTaxBps > MAX_TAX_BPS) {
            revert OfficialPool__TaxAboveMaximum(newTaxBps, MAX_TAX_BPS);
        }
        uint256 previousBps = s_taxBps;
        s_taxBps = newTaxBps;
        emit TaxBpsUpdated(previousBps, newTaxBps);
    }

    /// @notice Quotes a fixed input at the current reserves and tax.
    /// @param direction Buy or sell.
    /// @param amountIn Asset the trader would pay, in base units.
    /// @return amountOut Asset the trader would receive, in base units.
    /// @return usdcTax mUSDC tax, in base units.
    function quoteExactInput(Direction direction, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, uint256 usdcTax)
    {
        PoolMath.Result memory result =
            PoolMath.quoteExactInput(direction, s_reserveDvr, s_reserveUsdc, amountIn, s_taxBps);
        amountOut = result.amountOut;
        usdcTax = result.usdcTax;
    }

    /// @notice Quotes a fixed output at the current reserves and tax.
    /// @param direction Buy or sell.
    /// @param amountOut Asset the trader would receive, in base units.
    /// @return amountIn Asset the trader would pay, in base units.
    /// @return usdcTax mUSDC tax, in base units.
    function quoteExactOutput(Direction direction, uint256 amountOut)
        external
        view
        returns (uint256 amountIn, uint256 usdcTax)
    {
        PoolMath.Result memory result =
            PoolMath.quoteExactOutput(direction, s_reserveDvr, s_reserveUsdc, amountOut, s_taxBps);
        amountIn = result.amountIn;
        usdcTax = result.usdcTax;
    }

    /// @inheritdoc IOfficialPool
    function reserveDvr() external view returns (uint256 reserveDvr_) {
        reserveDvr_ = s_reserveDvr;
    }

    /// @inheritdoc IOfficialPool
    function reserveUsdc() external view returns (uint256 reserveUsdc_) {
        reserveUsdc_ = s_reserveUsdc;
    }

    /// @inheritdoc IOfficialPool
    function taxBps() external view returns (uint256 taxBps_) {
        taxBps_ = s_taxBps;
    }

    /// @dev Reverts when `block.timestamp` is after `deadline`.
    function _revertIfExpired(uint256 deadline) private view {
        if (block.timestamp > deadline) {
            revert OfficialPool__DeadlinePassed(deadline, block.timestamp);
        }
    }

    /// @dev Writes reserves, pulls the input, sends any tax, then pays the output.
    function _settle(Direction direction, PoolMath.Result memory result) private {
        s_reserveDvr = result.newReserveDvr;
        s_reserveUsdc = result.newReserveUsdc;
        _takeInput(direction, result.amountIn);
        _payTax(result.usdcTax);
        _payOutput(direction, result.amountOut);
        emit Swapped(msg.sender, direction, result.amountIn, result.amountOut, result.usdcTax);
    }

    /// @dev Pulls mUSDC on a buy and DVR on a sell.
    function _takeInput(Direction direction, uint256 amountIn) private {
        if (direction == Direction.Buy) {
            IERC20(i_usdc).safeTransferFrom(msg.sender, address(this), amountIn);
        } else {
            IERC20(i_dvr).safeTransferFrom(msg.sender, address(this), amountIn);
        }
    }

    /// @dev Sends `usdcTax` to the splitter and records it. A zero tax does not call the splitter.
    function _payTax(uint256 usdcTax) private {
        if (usdcTax == 0) {
            return;
        }
        IERC20(i_usdc).safeTransfer(address(i_taxSplitter), usdcTax);
        i_taxSplitter.accrue(usdcTax);
    }

    /// @dev Pays DVR on a buy and mUSDC on a sell.
    function _payOutput(Direction direction, uint256 amountOut) private {
        if (direction == Direction.Buy) {
            IERC20(i_dvr).safeTransfer(msg.sender, amountOut);
        } else {
            IERC20(i_usdc).safeTransfer(msg.sender, amountOut);
        }
    }
}
