// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {DriverToken} from "../src/DriverToken.sol";
import {DriverFaucet} from "../src/DriverFaucet.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../src/MockUsdcFaucet.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployDriverToken
/// @notice Deploys DriverToken, the DVR faucet, Mock USDC, and the Mock USDC faucet on Anvil or Sepolia.
contract DeployDriverToken is Script {
    /// @notice The DVR faucet allocation transfer returned false.
    error DeployDriverToken__TransferFailed();

    /// @notice Deploys the contracts, mints the setup balances, and funds the DVR faucet.
    /// @dev The pool, community pool, team reserve, and funds do not exist yet, so those allocations
    /// stay with the deployer. The DVR faucet receives {HelperConfig.FAUCET_ALLOCATION} by transfer in
    /// this broadcast. There is no extra mint and no approval. The Mock USDC faucet is the minter and
    /// receives no pre-minted balance.
    /// @return token The deployed DVR token.
    /// @return dvrFaucet The deployed DVR faucet.
    /// @return usdc The deployed Mock USDC token.
    /// @return usdcFaucet The deployed Mock USDC faucet.
    function run()
        external
        returns (DriverToken token, DriverFaucet dvrFaucet, MockUSDC usdc, MockUsdcFaucet usdcFaucet)
    {
        HelperConfig helper = new HelperConfig();
        address deployer = helper.getConfig().deployer;

        vm.startBroadcast(deployer);
        token = new DriverToken(deployer);
        token.mint(deployer, helper.POOL_ALLOCATION());
        token.mint(deployer, helper.FAUCET_ALLOCATION());
        token.mint(deployer, helper.COMMUNITY_ALLOCATION());
        token.mint(deployer, helper.TEAM_ALLOCATION());

        dvrFaucet = new DriverFaucet(
            token,
            helper.DVR_FAUCET_CLAIM_AMOUNT(),
            helper.DVR_FAUCET_CLAIM_COOLDOWN(),
            helper.DVR_FAUCET_DAILY_CLAIM_LIMIT()
        );
        if (!token.transfer(address(dvrFaucet), helper.FAUCET_ALLOCATION())) {
            revert DeployDriverToken__TransferFailed();
        }

        usdc = new MockUSDC(deployer);
        usdcFaucet = new MockUsdcFaucet(
            usdc,
            helper.USDC_FAUCET_CLAIM_AMOUNT(),
            helper.USDC_FAUCET_CLAIM_COOLDOWN(),
            helper.USDC_FAUCET_DAILY_CLAIM_LIMIT()
        );
        usdc.setMinter(address(usdcFaucet));
        usdc.mint(deployer, helper.POOL_USDC());
        usdc.mint(deployer, helper.FUND_1_USDC());
        usdc.mint(deployer, helper.FUND_2_USDC());
        usdc.mint(deployer, helper.FUND_3_USDC());
        vm.stopBroadcast();
    }
}
