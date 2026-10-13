// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Mock USDC
/// @notice Uncapped test token. The name is Mock USDC, the symbol is mUSDC, and amounts use 6 decimals.
/// @dev The owner mints deploy-time balances through {mint}. A separate minter, stored in `s_minter`,
/// mints through {mintFromFaucet}. The owner is not that minter unless {setMinter} says so.
/// This contract never calls another contract, so it does not use `ReentrancyGuard`. There is no burn
/// function and no lifetime cap. Transfers are the standard ERC-20 implementation.
contract MockUSDC is ERC20, Ownable2Step {
    address private s_minter;

    /// @notice Emitted when tokens are minted.
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount minted, in base units.
    event Minted(address indexed to, uint256 amount);

    /// @notice Emitted when the owner changes the faucet minter.
    /// @param previous Previous minter. The zero address means there was none.
    /// @param newMinter New minter. The zero address clears the faucet path.
    event MinterUpdated(address indexed previous, address indexed newMinter);

    /// @notice The mint amount was zero.
    error MockUSDC__ZeroAmount();

    /// @notice The caller is not the faucet minter.
    /// @param caller Account that called {mintFromFaucet}.
    error MockUSDC__CallerNotMinter(address caller);

    /// @notice Sets the token name, symbol, and initial owner. Does not mint.
    /// @param initialOwner Account allowed to mint and to set the minter. The zero address is rejected.
    constructor(address initialOwner) ERC20("Mock USDC", "mUSDC") Ownable(initialOwner) {}

    /// @notice Mints `amount` tokens to `to`.
    /// @dev Reverts with {MockUSDC__ZeroAmount} when `amount` is zero.
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount to mint, in base units. Must be greater than zero.
    function mint(address to, uint256 amount) external onlyOwner {
        _mintTo(to, amount);
    }

    /// @notice Sets the account allowed to call {mintFromFaucet}.
    /// @dev The zero address clears the minter and blocks {mintFromFaucet}. Setting the minter does not
    /// transfer ownership.
    /// @param newMinter Account that may mint through the faucet path. The zero address clears it.
    function setMinter(address newMinter) external onlyOwner {
        address previous = s_minter;
        s_minter = newMinter;
        emit MinterUpdated(previous, newMinter);
    }

    /// @notice Mints `amount` tokens to `to` from the faucet minter.
    /// @dev Reverts with {MockUSDC__CallerNotMinter} when the caller is not `s_minter`, including when the
    /// minter is unset. Reverts with {MockUSDC__ZeroAmount} when `amount` is zero.
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount to mint, in base units. Must be greater than zero.
    function mintFromFaucet(address to, uint256 amount) external {
        if (msg.sender != s_minter) {
            revert MockUSDC__CallerNotMinter(msg.sender);
        }
        _mintTo(to, amount);
    }

    /// @notice Returns the account allowed to call {mintFromFaucet}.
    /// @return minter_ The faucet minter. The zero address means the faucet path is closed.
    function minter() public view returns (address minter_) {
        minter_ = s_minter;
    }

    /// @notice Returns the number of decimals used to display amounts.
    /// @return decimals_ Six. One whole token is `10 ** 6` base units.
    function decimals() public pure override returns (uint8 decimals_) {
        decimals_ = 6;
    }

    /// @dev Reverts with {MockUSDC__ZeroAmount} when `amount` is zero, then mints and emits {Minted}.
    function _mintTo(address to, uint256 amount) internal {
        if (amount == 0) {
            revert MockUSDC__ZeroAmount();
        }
        _mint(to, amount);
        emit Minted(to, amount);
    }
}
