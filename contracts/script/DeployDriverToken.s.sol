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
import {MockFarm} from "../src/MockFarm.sol";
import {OfficialPool} from "../src/OfficialPool.sol";
import {TaxSplitter} from "../src/TaxSplitter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployDriverToken
/// @notice Deploys DriverToken, the faucets, the clock, the tax splitter, the official pool, and the four mock farms.
contract DeployDriverToken is Script {
    /// @notice The DVR faucet allocation transfer returned false.
    error DeployDriverToken__TransferFailed();

    /// @notice Deploys the contracts, mints the setup balances, funds the DVR faucet, seeds the pool, and funds the farms.
    /// @dev Community and team DVR stay with the deployer. Fund mUSDC stays with the deployer. The official
    /// pool receives {HelperConfig.POOL_ALLOCATION} and {HelperConfig.POOL_USDC}. The DVR faucet receives
    /// {HelperConfig.FAUCET_ALLOCATION} by transfer. The Mock USDC faucet is the minter and receives no
    /// pre-minted balance. Anvil deploys {DemoDriverClock}. Sepolia deploys {DriverClock}. The splitter and
    /// the pool are created after the clock. The starting tax is {HelperConfig.INITIAL_TAX_BPS}. After
    /// {OfficialPool.addLiquidity}, this deploys Cruise, Highway, Autobahn, and Drift, mints the sum of their
    /// reserves to the deployer in one call, then approves and calls {MockFarm.fundRewards} for that exact
    /// reserve on each farm, in that order. No depositor is added.
    /// @return token The deployed DVR token.
    /// @return dvrFaucet The deployed DVR faucet.
    /// @return usdc The deployed Mock USDC token.
    /// @return usdcFaucet The deployed Mock USDC faucet.
    /// @return clock The deployed clock.
    /// @return splitter The deployed tax splitter.
    /// @return pool The deployed official pool.
    /// @return cruise The Cruise mock farm.
    /// @return highway The Highway mock farm.
    /// @return autobahn The Autobahn mock farm.
    /// @return drift The Drift mock farm.
    function run()
        external
        returns (
            DriverToken token,
            DriverFaucet dvrFaucet,
            MockUSDC usdc,
            MockUsdcFaucet usdcFaucet,
            IDriverClock clock,
            TaxSplitter splitter,
            OfficialPool pool,
            MockFarm cruise,
            MockFarm highway,
            MockFarm autobahn,
            MockFarm drift
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

        splitter = new TaxSplitter(usdc, deployer);
        pool = new OfficialPool(token, usdc, splitter, deployer, helper.INITIAL_TAX_BPS());
        splitter.setPool(address(pool));
        token.approve(address(pool), helper.POOL_ALLOCATION());
        usdc.approve(address(pool), helper.POOL_USDC());
        pool.addLiquidity(helper.POOL_ALLOCATION(), helper.POOL_USDC());

        cruise = new MockFarm(usdc, clock, helper.CRUISE_APR_BPS(), deployer);
        highway = new MockFarm(usdc, clock, helper.HIGHWAY_APR_BPS(), deployer);
        autobahn = new MockFarm(usdc, clock, helper.AUTOBAHN_APR_BPS(), deployer);
        drift = new MockFarm(usdc, clock, helper.DRIFT_APR_BPS(), deployer);
        usdc.mint(
            deployer,
            helper.CRUISE_RESERVE() + helper.HIGHWAY_RESERVE() + helper.AUTOBAHN_RESERVE() + helper.DRIFT_RESERVE()
        );
        usdc.approve(address(cruise), helper.CRUISE_RESERVE());
        cruise.fundRewards(helper.CRUISE_RESERVE());
        usdc.approve(address(highway), helper.HIGHWAY_RESERVE());
        highway.fundRewards(helper.HIGHWAY_RESERVE());
        usdc.approve(address(autobahn), helper.AUTOBAHN_RESERVE());
        autobahn.fundRewards(helper.AUTOBAHN_RESERVE());
        usdc.approve(address(drift), helper.DRIFT_RESERVE());
        drift.fundRewards(helper.DRIFT_RESERVE());
        vm.stopBroadcast();
    }
}
