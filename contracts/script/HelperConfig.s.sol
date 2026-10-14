// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

/// @title HelperConfig
/// @notice Per-chain deploy parameters for Anvil and Sepolia.
contract HelperConfig is Script {
    struct NetworkConfig {
        address deployer;
    }

    /// @notice Chain id of a local Anvil node.
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    /// @notice Chain id of Ethereum Sepolia.
    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

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

    /// @notice Sepolia was selected and the deployer address was missing or zero.
    error HelperConfig__SepoliaDeployerNotSet();

    /// @notice Resolves deploy parameters for one chain.
    /// @dev Anvil ignores `sepoliaDeployer`. Sepolia reverts when that address is zero.
    /// @param chainId Chain id to resolve.
    /// @param sepoliaDeployer Deployer address used when `chainId` is Sepolia.
    /// @return config Deploy parameters for `chainId`.
    function configFor(uint256 chainId, address sepoliaDeployer) public pure returns (NetworkConfig memory config) {
        if (chainId == ANVIL_CHAIN_ID) {
            config = NetworkConfig({deployer: ANVIL_DEPLOYER});
        } else if (chainId == SEPOLIA_CHAIN_ID) {
            if (sepoliaDeployer == address(0)) {
                revert HelperConfig__SepoliaDeployerNotSet();
            }
            config = NetworkConfig({deployer: sepoliaDeployer});
        } else {
            revert HelperConfig__ChainNotSupported(chainId);
        }
    }

    /// @notice Returns the deployer for the active chain.
    /// @dev Reads `SEPOLIA_DEPLOYER` only when the active chain is Sepolia.
    /// @return config Deploy parameters for this chain.
    function getConfig() public view returns (NetworkConfig memory config) {
        address sepoliaDeployer =
            block.chainid == SEPOLIA_CHAIN_ID ? vm.envOr("SEPOLIA_DEPLOYER", address(0)) : address(0);
        config = configFor(block.chainid, sepoliaDeployer);
    }
}
