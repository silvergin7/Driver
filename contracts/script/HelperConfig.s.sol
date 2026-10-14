// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

/// @title HelperConfig
/// @notice Per-chain deploy parameters. Anvil is the only chain configured on this branch.
contract HelperConfig is Script {
    struct NetworkConfig {
        address deployer;
    }

    /// @notice Chain id of a local Anvil node.
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    /// @notice Anvil default account 0.
    address public constant ANVIL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    /// @notice DVR allocated to official pool liquidity.
    uint256 public constant POOL_ALLOCATION = 500_000 * 10 ** 18;

    /// @notice DVR allocated to the faucet. This is the faucet's entire lifetime balance.
    uint256 public constant FAUCET_ALLOCATION = 50_000 * 10 ** 18;

    /// @notice DVR allocated to the community reward pool.
    uint256 public constant COMMUNITY_ALLOCATION = 300_000 * 10 ** 18;

    /// @notice DVR allocated to the team reserve.
    uint256 public constant TEAM_ALLOCATION = 150_000 * 10 ** 18;

    /// @notice DVR transferred by one faucet claim, in base units.
    uint256 public constant DVR_FAUCET_CLAIM_AMOUNT = 10 * 10 ** 18;

    /// @notice Minimum time between two DVR claims by the same wallet.
    uint256 public constant DVR_FAUCET_CLAIM_COOLDOWN = 24 hours;

    /// @notice Maximum DVR faucet claims across all wallets in one UTC day.
    uint256 public constant DVR_FAUCET_DAILY_CLAIM_LIMIT = 25;

    /// @notice Mock USDC minted by one faucet claim, in base units.
    uint256 public constant USDC_FAUCET_CLAIM_AMOUNT = 100 * 10 ** 6;

    /// @notice Minimum time between two Mock USDC claims by the same wallet.
    uint256 public constant USDC_FAUCET_CLAIM_COOLDOWN = 24 hours;

    /// @notice Maximum Mock USDC faucet claims across all wallets in one UTC day.
    uint256 public constant USDC_FAUCET_DAILY_CLAIM_LIMIT = 25;

    /// @notice Mock USDC seeded as official pool liquidity.
    uint256 public constant POOL_USDC = 10_000 * 10 ** 6;

    /// @notice Mock USDC allocated to Fund 1.
    uint256 public constant FUND_1_USDC = 15_000 * 10 ** 6;

    /// @notice Mock USDC allocated to Fund 2.
    uint256 public constant FUND_2_USDC = 5_000 * 10 ** 6;

    /// @notice Mock USDC allocated to Fund 3.
    uint256 public constant FUND_3_USDC = 5_000 * 10 ** 6;

    /// @notice No deploy parameters exist for this chain yet.
    /// @param chainId The active chain id.
    error HelperConfig__ChainNotSupported(uint256 chainId);

    /// @notice Returns the deployer for the active chain.
    /// @return config Deploy parameters for this chain.
    function getConfig() public view returns (NetworkConfig memory config) {
        if (block.chainid != ANVIL_CHAIN_ID) {
            revert HelperConfig__ChainNotSupported(block.chainid);
        }
        config = NetworkConfig({deployer: ANVIL_DEPLOYER});
    }
}
