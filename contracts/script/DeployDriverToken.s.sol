// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {DriverToken} from "../src/DriverToken.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../src/MockUsdcFaucet.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployDriverToken
/// @notice Deploys DriverToken, Mock USDC, and the Mock USDC faucet on Anvil.
contract DeployDriverToken is Script {
    /// @notice Deploys the contracts and mints the setup balances to the configured deployer.
    /// @dev The pool, DVR faucet, community pool, team reserve, and funds do not exist yet, so every
    /// allocation is minted to the deployer. Later deploys change the recipient, not the amount.
    /// The Mock USDC faucet is the minter and receives no pre-minted balance.
    /// @return token The deployed DVR token.
    /// @return usdc The deployed Mock USDC token.
    /// @return faucet The deployed Mock USDC faucet.
    function run() external returns (DriverToken token, MockUSDC usdc, MockUsdcFaucet faucet) {
        HelperConfig helper = new HelperConfig();
        address deployer = helper.getConfig().deployer;

        vm.startBroadcast(deployer);
        token = new DriverToken(deployer);
        token.mint(deployer, helper.POOL_ALLOCATION());
        token.mint(deployer, helper.FAUCET_ALLOCATION());
        token.mint(deployer, helper.COMMUNITY_ALLOCATION());
        token.mint(deployer, helper.TEAM_ALLOCATION());

        usdc = new MockUSDC(deployer);
        faucet = new MockUsdcFaucet(
            usdc,
            helper.USDC_FAUCET_CLAIM_AMOUNT(),
            helper.USDC_FAUCET_CLAIM_COOLDOWN(),
            helper.USDC_FAUCET_DAILY_CLAIM_LIMIT()
        );
        usdc.setMinter(address(faucet));
        usdc.mint(deployer, helper.POOL_USDC());
        usdc.mint(deployer, helper.FUND_1_USDC());
        usdc.mint(deployer, helper.FUND_2_USDC());
        usdc.mint(deployer, helper.FUND_3_USDC());
        vm.stopBroadcast();
    }
}
