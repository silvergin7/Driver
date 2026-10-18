// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IDriverClock} from "../src/interfaces/IDriverClock.sol";
import {IMockFarm} from "../src/interfaces/IMockFarm.sol";
import {CruiseControl} from "../src/CruiseControl.sol";
import {DegenDriver} from "../src/DegenDriver.sol";
import {DriverClock} from "../src/DriverClock.sol";
import {DemoDriverClock} from "../src/DemoDriverClock.sol";
import {DriverToken} from "../src/DriverToken.sol";
import {DriverFaucet} from "../src/DriverFaucet.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../src/MockUsdcFaucet.sol";
import {MockFarm} from "../src/MockFarm.sol";
import {OfficialPool} from "../src/OfficialPool.sol";
import {RoundSchedule} from "../src/RoundSchedule.sol";
import {TaxSplitter} from "../src/TaxSplitter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployDriverToken
/// @notice Deploys DriverToken, the faucets, the clock, the tax splitter, the official pool, the four mock farms, and the two funds.
contract DeployDriverToken is Script {
    /// @notice Contracts created by {run}.
    struct Deployed {
        DriverToken token;
        DriverFaucet dvrFaucet;
        MockUSDC usdc;
        MockUsdcFaucet usdcFaucet;
        IDriverClock clock;
        TaxSplitter splitter;
        OfficialPool pool;
        MockFarm cruise;
        MockFarm highway;
        MockFarm autobahn;
        MockFarm drift;
        RoundSchedule schedule;
        CruiseControl cruiseControl;
        DegenDriver degenDriver;
    }

    /// @notice The DVR faucet allocation transfer returned false.
    error DeployDriverToken__TransferFailed();

    /// @notice Deploys the contracts, mints the setup balances, funds the DVR faucet, seeds the pool, funds the farms, and seeds the two funds.
    /// @dev Community and team DVR stay with the deployer. Fund 3's mUSDC stays with the deployer. The official
    /// pool receives {HelperConfig.POOL_ALLOCATION} and {HelperConfig.POOL_USDC}. The DVR faucet receives
    /// {HelperConfig.FAUCET_ALLOCATION} by transfer. The Mock USDC faucet is the minter and receives no
    /// pre-minted balance. Anvil deploys {DemoDriverClock}. Sepolia deploys {DriverClock}. The splitter and
    /// the pool are created after the clock. The starting tax is {HelperConfig.INITIAL_TAX_BPS}. After
    /// {OfficialPool.addLiquidity}, this deploys Cruise, Highway, Autobahn, and Drift, mints the sum of their
    /// reserves to the deployer in one call, then approves and calls {MockFarm.fundRewards} for that exact
    /// reserve on each farm, in that order. It then deploys {RoundSchedule} for {HelperConfig.EPOCH_LENGTH},
    /// {CruiseControl} with Cruise only, and {DegenDriver} with Highway, Autobahn, and Drift. Both funds
    /// receive {HelperConfig.FUND_1_USDC} and {HelperConfig.FUND_2_USDC} as their starting shares. Degen Driver
    /// is constructed with Cruise Control. It supplies {HelperConfig.FUND_1_USDC} and {HelperConfig.FUND_2_USDC},
    /// adds the funds as depositors, selects Cruise, and deposits Fund 1. The splitter's Fund 1 and Fund 2
    /// recipients are the two funds. Fund 3 has no recipient. {CruiseControl.setFund2} runs last. Nothing
    /// rebalances. Nothing is paused.
    /// @return deployed The deployed contracts.
    function run() external returns (Deployed memory deployed) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helper.getConfig();
        address deployer = config.deployer;

        vm.startBroadcast(deployer);
        deployed.token = new DriverToken(deployer);
        deployed.token.mint(deployer, helper.POOL_ALLOCATION());
        deployed.token.mint(deployer, helper.FAUCET_ALLOCATION());
        deployed.token.mint(deployer, helper.COMMUNITY_ALLOCATION());
        deployed.token.mint(deployer, helper.TEAM_ALLOCATION());

        deployed.dvrFaucet = new DriverFaucet(
            deployed.token,
            helper.DVR_FAUCET_CLAIM_AMOUNT(),
            helper.DVR_FAUCET_CLAIM_COOLDOWN(),
            helper.DVR_FAUCET_DAILY_CLAIM_LIMIT()
        );
        if (!deployed.token.transfer(address(deployed.dvrFaucet), helper.FAUCET_ALLOCATION())) {
            revert DeployDriverToken__TransferFailed();
        }

        deployed.usdc = new MockUSDC(deployer);
        deployed.usdcFaucet = new MockUsdcFaucet(
            deployed.usdc,
            helper.USDC_FAUCET_CLAIM_AMOUNT(),
            helper.USDC_FAUCET_CLAIM_COOLDOWN(),
            helper.USDC_FAUCET_DAILY_CLAIM_LIMIT()
        );
        deployed.usdc.setMinter(address(deployed.usdcFaucet));
        deployed.usdc.mint(deployer, helper.POOL_USDC());
        deployed.usdc.mint(deployer, helper.FUND_1_USDC());
        deployed.usdc.mint(deployer, helper.FUND_2_USDC());
        deployed.usdc.mint(deployer, helper.FUND_3_USDC());
        if (config.demoClock) {
            deployed.clock = new DemoDriverClock(deployer);
        } else {
            deployed.clock = new DriverClock();
        }

        deployed.splitter = new TaxSplitter(deployed.usdc, deployer);
        deployed.pool =
            new OfficialPool(deployed.token, deployed.usdc, deployed.splitter, deployer, helper.INITIAL_TAX_BPS());
        deployed.splitter.setPool(address(deployed.pool));
        deployed.token.approve(address(deployed.pool), helper.POOL_ALLOCATION());
        deployed.usdc.approve(address(deployed.pool), helper.POOL_USDC());
        deployed.pool.addLiquidity(helper.POOL_ALLOCATION(), helper.POOL_USDC());

        deployed.cruise = new MockFarm(deployed.usdc, deployed.clock, helper.CRUISE_APR_BPS(), deployer);
        deployed.highway = new MockFarm(deployed.usdc, deployed.clock, helper.HIGHWAY_APR_BPS(), deployer);
        deployed.autobahn = new MockFarm(deployed.usdc, deployed.clock, helper.AUTOBAHN_APR_BPS(), deployer);
        deployed.drift = new MockFarm(deployed.usdc, deployed.clock, helper.DRIFT_APR_BPS(), deployer);
        deployed.usdc
            .mint(
                deployer,
                helper.CRUISE_RESERVE() + helper.HIGHWAY_RESERVE() + helper.AUTOBAHN_RESERVE() + helper.DRIFT_RESERVE()
            );
        _fundFarm(deployed.usdc, deployed.cruise, helper.CRUISE_RESERVE());
        _fundFarm(deployed.usdc, deployed.highway, helper.HIGHWAY_RESERVE());
        _fundFarm(deployed.usdc, deployed.autobahn, helper.AUTOBAHN_RESERVE());
        _fundFarm(deployed.usdc, deployed.drift, helper.DRIFT_RESERVE());
        _seedFunds(deployed, helper, deployer);
        vm.stopBroadcast();
    }

    /// @dev Approves `reserve` and calls {MockFarm.fundRewards} for that exact amount.
    function _fundFarm(MockUSDC usdc, MockFarm farm, uint256 reserve) private {
        usdc.approve(address(farm), reserve);
        farm.fundRewards(reserve);
    }

    /// @dev Creates the schedule, supplies both funds, adds the planned depositors, deposits Fund 1 into Cruise, sets Fund 1 and Fund 2 recipients, and stores Fund 2 on Fund 1.
    function _seedFunds(Deployed memory deployed, HelperConfig helper, address deployer) private {
        deployed.schedule = new RoundSchedule(deployed.clock, helper.EPOCH_LENGTH());
        deployed.cruiseControl = new CruiseControl(
            deployed.usdc,
            deployed.clock,
            deployed.schedule,
            deployed.splitter,
            deployed.pool,
            helper.FUND_1_USDC(),
            helper.FUND_2_USDC(),
            _cruiseFarms(deployed.cruise),
            deployer
        );
        deployed.degenDriver = new DegenDriver(
            deployed.usdc,
            deployed.clock,
            deployed.schedule,
            deployed.splitter,
            deployed.pool,
            deployed.cruiseControl,
            helper.FUND_1_USDC(),
            helper.FUND_2_USDC(),
            _degenFarms(deployed.highway, deployed.autobahn, deployed.drift),
            deployer
        );
        deployed.usdc.approve(address(deployed.cruiseControl), helper.FUND_1_USDC());
        deployed.cruiseControl.supply(helper.FUND_1_USDC());
        deployed.usdc.approve(address(deployed.degenDriver), helper.FUND_2_USDC());
        deployed.degenDriver.supply(helper.FUND_2_USDC());
        deployed.cruise.addDepositor(address(deployed.cruiseControl));
        deployed.highway.addDepositor(address(deployed.degenDriver));
        deployed.autobahn.addDepositor(address(deployed.degenDriver));
        deployed.drift.addDepositor(address(deployed.degenDriver));
        deployed.cruiseControl.setStrategy(deployed.cruise);
        deployed.cruiseControl.deposit(helper.FUND_1_USDC());
        deployed.splitter.setRecipient(TaxSplitter.FundId.Fund1, address(deployed.cruiseControl));
        deployed.splitter.setRecipient(TaxSplitter.FundId.Fund2, address(deployed.degenDriver));
        deployed.cruiseControl.setFund2(deployed.degenDriver);
    }

    /// @dev One-entry list for {CruiseControl}. The entry is Cruise.
    function _cruiseFarms(MockFarm cruise) private pure returns (IMockFarm[] memory farms) {
        farms = new IMockFarm[](1);
        farms[0] = cruise;
    }

    /// @dev Highway, Autobahn, then Drift.
    function _degenFarms(MockFarm highway, MockFarm autobahn, MockFarm drift)
        private
        pure
        returns (IMockFarm[] memory farms)
    {
        farms = new IMockFarm[](3);
        farms[0] = highway;
        farms[1] = autobahn;
        farms[2] = drift;
    }
}
