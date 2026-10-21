// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

/// @title HelperConfig
/// @notice Per-chain deploy parameters for Anvil and Sepolia.
contract HelperConfig is Script {
    /// @notice Which clock a deploy creates. Production is the fixed clock. Demo can be advanced.
    enum DeployProfile {
        Production,
        Demo
    }

    struct NetworkConfig {
        address deployer;
        DeployProfile profile;
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

    /// @notice Starting official-pool tax, in basis points. 100 is 1 percent.
    uint256 public constant INITIAL_TAX_BPS = 100;

    /// @notice Length of one harvest and voting round. The same value on every chain.
    uint256 public constant EPOCH_LENGTH = 30 days;

    /// @notice Cruise farm APR, in basis points. 500 is 5 percent. Fund 1 only.
    uint256 public constant CRUISE_APR_BPS = 500;

    /// @notice Highway farm APR, in basis points. 4_000 is 40 percent. Fund 2 vote option.
    uint256 public constant HIGHWAY_APR_BPS = 4_000;

    /// @notice Autobahn farm APR, in basis points. 8_000 is 80 percent. Fund 2 vote option.
    uint256 public constant AUTOBAHN_APR_BPS = 8_000;

    /// @notice Drift farm APR, in basis points. 16_000 is 160 percent. Fund 2 vote option.
    uint256 public constant DRIFT_APR_BPS = 16_000;

    /// @notice Expected maximum Cruise principal, in mUSDC base units.
    uint256 public constant CRUISE_MAX_BALANCE = 30_000 * 10 ** 6;

    /// @notice Expected maximum Highway principal, in mUSDC base units.
    uint256 public constant HIGHWAY_MAX_BALANCE = 15_000 * 10 ** 6;

    /// @notice Expected maximum Autobahn principal, in mUSDC base units.
    uint256 public constant AUTOBAHN_MAX_BALANCE = 15_000 * 10 ** 6;

    /// @notice Expected maximum Drift principal, in mUSDC base units.
    uint256 public constant DRIFT_MAX_BALANCE = 30_000 * 10 ** 6;

    /// @notice Cruise reward reserve, in mUSDC base units. Two years of {CRUISE_APR_BPS} on {CRUISE_MAX_BALANCE}.
    uint256 public constant CRUISE_RESERVE = 3_000 * 10 ** 6;

    /// @notice Highway reward reserve, in mUSDC base units. Two years of {HIGHWAY_APR_BPS} on {HIGHWAY_MAX_BALANCE}.
    uint256 public constant HIGHWAY_RESERVE = 12_000 * 10 ** 6;

    /// @notice Autobahn reward reserve, in mUSDC base units. Two years of {AUTOBAHN_APR_BPS} on {AUTOBAHN_MAX_BALANCE}.
    uint256 public constant AUTOBAHN_RESERVE = 24_000 * 10 ** 6;

    /// @notice Drift reward reserve, in mUSDC base units. Two years of {DRIFT_APR_BPS} on {DRIFT_MAX_BALANCE}.
    uint256 public constant DRIFT_RESERVE = 96_000 * 10 ** 6;

    /// @notice No deploy parameters exist for this chain yet.
    /// @param chainId The active chain id.
    error HelperConfig__ChainNotSupported(uint256 chainId);

    /// @notice Sepolia was selected and the deployer address was missing or zero.
    error HelperConfig__SepoliaDeployerNotSet();

    /// @notice Sepolia was selected and `DEPLOY_PROFILE` was missing or empty.
    error HelperConfig__DeployProfileNotSet();

    /// @notice Sepolia was selected and `DEPLOY_PROFILE` was not `production` or `demo`.
    /// @param value The raw profile value.
    error HelperConfig__DeployProfileInvalid(string value);

    /// @notice Resolves deploy parameters for one chain and one profile.
    /// @dev Anvil ignores `sepoliaDeployer` and keeps `profile`. Sepolia reverts when that address is zero.
    /// @param chainId Chain id to resolve.
    /// @param sepoliaDeployer Deployer address used when `chainId` is Sepolia.
    /// @param profile Clock profile to store.
    /// @return config Deploy parameters for `chainId`.
    function configFor(uint256 chainId, address sepoliaDeployer, DeployProfile profile)
        public
        pure
        returns (NetworkConfig memory config)
    {
        if (chainId == ANVIL_CHAIN_ID) {
            config = NetworkConfig({deployer: ANVIL_DEPLOYER, profile: profile});
        } else if (chainId == SEPOLIA_CHAIN_ID) {
            if (sepoliaDeployer == address(0)) {
                revert HelperConfig__SepoliaDeployerNotSet();
            }
            config = NetworkConfig({deployer: sepoliaDeployer, profile: profile});
        } else {
            revert HelperConfig__ChainNotSupported(chainId);
        }
    }

    /// @notice Resolves Sepolia parameters from the deployer and the raw profile value.
    /// @dev A zero deployer reverts {HelperConfig__SepoliaDeployerNotSet} before the profile is read.
    /// An empty value reverts {HelperConfig__DeployProfileNotSet}. Only the exact strings `production`
    /// and `demo` are accepted.
    /// @param sepoliaDeployer Deployer address. Zero reverts.
    /// @param profileValue Raw `DEPLOY_PROFILE` value.
    /// @return config Sepolia deploy parameters.
    function sepoliaConfigFor(address sepoliaDeployer, string memory profileValue)
        public
        pure
        returns (NetworkConfig memory config)
    {
        if (sepoliaDeployer == address(0)) {
            revert HelperConfig__SepoliaDeployerNotSet();
        }
        config = configFor(SEPOLIA_CHAIN_ID, sepoliaDeployer, _profileFrom(profileValue));
    }

    /// @notice Returns deploy parameters for the active chain.
    /// @dev Anvil selects {DeployProfile.Demo} and reads no environment variables. Sepolia reads
    /// `SEPOLIA_DEPLOYER` and `DEPLOY_PROFILE`. Any other chain reverts and reads neither.
    /// @return config Deploy parameters for this chain.
    function getConfig() public view returns (NetworkConfig memory config) {
        if (block.chainid == ANVIL_CHAIN_ID) {
            config = configFor(ANVIL_CHAIN_ID, address(0), DeployProfile.Demo);
        } else if (block.chainid == SEPOLIA_CHAIN_ID) {
            config = sepoliaConfigFor(vm.envOr("SEPOLIA_DEPLOYER", address(0)), vm.envOr("DEPLOY_PROFILE", string("")));
        } else {
            revert HelperConfig__ChainNotSupported(block.chainid);
        }
    }

    /// @dev Accepts only an exact `production` or `demo`. Empty reverts {HelperConfig__DeployProfileNotSet}.
    function _profileFrom(string memory value) private pure returns (DeployProfile profile) {
        if (bytes(value).length == 0) {
            revert HelperConfig__DeployProfileNotSet();
        }
        bytes32 hashed = keccak256(bytes(value));
        if (hashed == keccak256(bytes("production"))) {
            profile = DeployProfile.Production;
        } else if (hashed == keccak256(bytes("demo"))) {
            profile = DeployProfile.Demo;
        } else {
            revert HelperConfig__DeployProfileInvalid(value);
        }
    }
}
