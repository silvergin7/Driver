// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IDriverClock} from "../src/interfaces/IDriverClock.sol";
import {DriverClock} from "../src/DriverClock.sol";
import {DemoDriverClock} from "../src/DemoDriverClock.sol";
import {DriverToken} from "../src/DriverToken.sol";
import {DriverFaucet} from "../src/DriverFaucet.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../src/MockUsdcFaucet.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployDriverToken
/// @notice Deploys DriverToken, the DVR faucet, Mock USDC, the Mock USDC faucet, and the shared clock.
contract DeployDriverToken is Script {
    /// @notice The DVR faucet allocation transfer returned false.
    error DeployDriverToken__TransferFailed();

    /// @notice Deploys the contracts, mints the setup balances, and funds the DVR faucet.
    /// @dev The pool, community pool, team reserve, and funds do not exist yet, so those allocations
    /// stay with the deployer. The DVR faucet receives {HelperConfig.FAUCET_ALLOCATION} by transfer in
    /// this broadcast. There is no extra mint and no approval. The Mock USDC faucet is the minter and
    /// receives no pre-minted balance. The clock is created last. Anvil deploys {DemoDriverClock}.
    /// Sepolia deploys {DriverClock}.
    /// @return token The deployed DVR token.
    /// @return dvrFaucet The deployed DVR faucet.
    /// @return usdc The deployed Mock USDC token.
    /// @return usdcFaucet The deployed Mock USDC faucet.
    /// @return clock The deployed clock.
    function run()
        external
        returns (
            DriverToken token,
            DriverFaucet dvrFaucet,
            MockUSDC usdc,
            MockUsdcFaucet usdcFaucet,
            IDriverClock clock
        )
    {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helper.getConfig();
        address deployer = config.deployer;

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
        if (config.demoClock) {
            clock = new DemoDriverClock(deployer);
        } else {
            clock = new DriverClock();
        }
        vm.stopBroadcast();
    }
}
