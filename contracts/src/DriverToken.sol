// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Driver
/// @notice Lifetime-capped ERC-20. The name is Driver, the symbol is DVR, and amounts use 18 decimals.
/// @dev The owner mints through {mint}. Every mint is counted in `s_totalMinted` inside {_update},
/// including any future path that mints through that hook. Burning reduces the current supply and
/// does not restore mintable tokens. This contract never calls another contract, so it does not use
/// `ReentrancyGuard`. Transfers are the standard ERC-20 implementation: no fee and no restriction.
contract DriverToken is ERC20Burnable, Ownable2Step {
    /// @notice Lifetime maximum of tokens that can ever be minted.
    uint256 public constant MAX_SUPPLY = 1_000_000 * 10 ** 18;

    uint256 private s_totalMinted;

    /// @notice Emitted when the owner mints tokens.
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount minted, in token units.
    event Minted(address indexed to, uint256 amount);

    /// @notice The mint would push lifetime minted supply above {MAX_SUPPLY}.
    /// @param totalMinted Lifetime amount already minted.
    /// @param amount Amount requested by this mint.
    /// @param maxSupply The lifetime cap.
    error DriverToken__LifetimeMintCapExceeded(uint256 totalMinted, uint256 amount, uint256 maxSupply);

    /// @notice The mint amount was zero.
    error DriverToken__ZeroAmount();

    /// @notice Sets the token name, symbol, and initial owner. Does not mint.
    /// @param initialOwner Account allowed to mint. The zero address is rejected.
    constructor(address initialOwner) ERC20("Driver", "DVR") Ownable(initialOwner) {}

    /// @notice Mints `amount` tokens to `to` and counts them against the lifetime cap.
    /// @dev Reverts with {DriverToken__ZeroAmount} when `amount` is zero, and with
    /// {DriverToken__LifetimeMintCapExceeded} when the lifetime cap would be exceeded.
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount to mint, in token units. Must be greater than zero.
    function mint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) {
            revert DriverToken__ZeroAmount();
        }
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /// @notice Returns the lifetime amount minted.
    /// @return totalMinted_ Lifetime minted supply. Burns do not reduce this value.
    function totalMinted() external view returns (uint256 totalMinted_) {
        totalMinted_ = s_totalMinted;
    }

    /// @dev On a mint (`from` is the zero address), reverts when `value` is greater than the
    /// remaining lifetime room, then increases `s_totalMinted`. The comparison uses subtraction
    /// so an amount near `type(uint256).max` still reverts with {DriverToken__LifetimeMintCapExceeded}
    /// instead of overflowing the addition. Burns and transfers do not change `s_totalMinted`.
    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0)) {
            if (value > MAX_SUPPLY - s_totalMinted) {
                revert DriverToken__LifetimeMintCapExceeded(s_totalMinted, value, MAX_SUPPLY);
            }
            s_totalMinted += value;
        }
        super._update(from, to, value);
    }
}
