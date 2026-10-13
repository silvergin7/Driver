// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {DriverToken} from "../src/DriverToken.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployDriverToken
/// @notice Deploys DriverToken and mints the full supply to the configured deployer.
contract DeployDriverToken is Script {
    /// @notice Deploys the token and mints each allocation to the deployer.
    /// @dev The pool, faucet, community pool, and team reserve do not exist yet, so every
    /// allocation is minted to the deployer. Later deploys change the recipient, not the amount.
    /// @return token The deployed token.
    function run() external returns (DriverToken token) {
        HelperConfig helper = new HelperConfig();
        address deployer = helper.getConfig().deployer;

        vm.startBroadcast(deployer);
        token = new DriverToken(deployer);
        token.mint(deployer, helper.POOL_ALLOCATION());
        token.mint(deployer, helper.FAUCET_ALLOCATION());
        token.mint(deployer, helper.COMMUNITY_ALLOCATION());
        token.mint(deployer, helper.TEAM_ALLOCATION());
        vm.stopBroadcast();
    }
}
