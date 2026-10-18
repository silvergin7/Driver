// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";
import {DriverClock} from "../../src/DriverClock.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverFaucet} from "../../src/DriverFaucet.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../../src/MockUsdcFaucet.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";
import {DeployDriverToken} from "../../script/DeployDriverToken.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DeployDriverTokenTest is Test {
    function test_AnvilDeployMintsFullSupplyAndFundsFaucet() public {
        HelperConfig helper = new HelperConfig();
        DeployDriverToken.Deployed memory deployed = new DeployDriverToken().run();
        DriverToken token = deployed.token;
        DriverFaucet dvrFaucet = deployed.dvrFaucet;
        OfficialPool pool = deployed.pool;
        MockFarm cruise = deployed.cruise;
        MockFarm highway = deployed.highway;
        MockFarm autobahn = deployed.autobahn;
        MockFarm drift = deployed.drift;
        address deployer = helper.ANVIL_DEPLOYER();
        _assertSeed(helper, deployer, deployed);
        assertEq(
            cruise.totalPrincipal() + highway.totalPrincipal() + autobahn.totalPrincipal() + drift.totalPrincipal(),
            helper.FUND_1_USDC()
        );
        uint256 maxSupply = token.MAX_SUPPLY();

        assertEq(token.owner(), deployer);
        assertEq(token.totalMinted(), maxSupply);
        assertEq(token.totalSupply(), maxSupply);
        assertEq(token.balanceOf(address(dvrFaucet)), helper.FAUCET_ALLOCATION());
        assertEq(token.balanceOf(address(pool)), helper.POOL_ALLOCATION());
        assertEq(token.balanceOf(deployer), helper.COMMUNITY_ALLOCATION() + helper.TEAM_ALLOCATION());
        assertEq(address(dvrFaucet.i_token()), address(token));
        assertEq(dvrFaucet.i_claimAmount(), helper.DVR_FAUCET_CLAIM_AMOUNT());
        assertEq(dvrFaucet.i_claimCooldown(), helper.DVR_FAUCET_CLAIM_COOLDOWN());
        assertEq(dvrFaucet.i_dailyClaimLimit(), helper.DVR_FAUCET_DAILY_CLAIM_LIMIT());

        address user = makeAddr("user");
        vm.prank(user);
        dvrFaucet.claim();
        assertEq(token.balanceOf(user), 10 * 10 ** 18);
        assertEq(token.balanceOf(address(dvrFaucet)), helper.FAUCET_ALLOCATION() - 10 * 10 ** 18);
        assertEq(token.totalMinted(), maxSupply);

        vm.expectRevert(
            abi.encodeWithSelector(DriverToken.DriverToken__LifetimeMintCapExceeded.selector, maxSupply, 1, maxSupply)
        );
        vm.prank(deployer);
        token.mint(deployer, 1);
    }

    function test_AnvilDeployMintsUsdcSetupBalancesAndSetsFaucetMinter() public {
        HelperConfig helper = new HelperConfig();
        DeployDriverToken.Deployed memory deployed = new DeployDriverToken().run();
        MockUSDC usdc = deployed.usdc;
        MockUsdcFaucet faucet = deployed.usdcFaucet;
        OfficialPool pool = deployed.pool;
        MockFarm cruise = deployed.cruise;
        MockFarm highway = deployed.highway;
        MockFarm autobahn = deployed.autobahn;
        MockFarm drift = deployed.drift;
        address deployer = helper.ANVIL_DEPLOYER();
        uint256 deployerBalance = helper.FUND_3_USDC();
        _assertSeed(helper, deployer, deployed);

        assertEq(usdc.owner(), deployer);
        assertEq(usdc.minter(), address(faucet));
        assertTrue(usdc.owner() != address(faucet));
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(cruise)), helper.CRUISE_RESERVE() + helper.FUND_1_USDC());
        assertEq(usdc.balanceOf(address(highway)), helper.HIGHWAY_RESERVE());
        assertEq(usdc.balanceOf(address(autobahn)), helper.AUTOBAHN_RESERVE());
        assertEq(usdc.balanceOf(address(drift)), helper.DRIFT_RESERVE());
        assertEq(usdc.balanceOf(deployer), deployerBalance);
        assertEq(usdc.balanceOf(address(pool)), helper.POOL_USDC());
        assertEq(usdc.balanceOf(address(faucet)), 0);
        assertEq(address(faucet.i_usdc()), address(usdc));
        assertEq(faucet.i_claimAmount(), helper.USDC_FAUCET_CLAIM_AMOUNT());
        assertEq(faucet.i_claimCooldown(), helper.USDC_FAUCET_CLAIM_COOLDOWN());
        assertEq(faucet.i_dailyClaimLimit(), helper.USDC_FAUCET_DAILY_CLAIM_LIMIT());

        address user = makeAddr("user");
        vm.prank(user);
        faucet.claim();
        assertEq(usdc.balanceOf(user), 100 * 10 ** 6);
        assertEq(usdc.balanceOf(address(faucet)), 0);

        vm.prank(deployer);
        usdc.mint(deployer, 1);
        assertEq(usdc.balanceOf(deployer), deployerBalance + 1);
    }

    function test_AnvilDeployAppendsDemoClock() public {
        HelperConfig helper = new HelperConfig();
        uint256 deployerDvr = helper.COMMUNITY_ALLOCATION() + helper.TEAM_ALLOCATION();
        uint256 deployerUsdc = helper.FUND_3_USDC();
        DeployDriverToken.Deployed memory deployed = new DeployDriverToken().run();
        DriverToken token = deployed.token;
        DriverFaucet dvrFaucet = deployed.dvrFaucet;
        MockUSDC usdc = deployed.usdc;
        MockUsdcFaucet usdcFaucet = deployed.usdcFaucet;
        IDriverClock clock = deployed.clock;
        TaxSplitter splitter = deployed.splitter;
        OfficialPool pool = deployed.pool;
        address deployer = helper.ANVIL_DEPLOYER();
        _assertSeed(helper, deployer, deployed);
        assertEq(address(token), 0x5FbDB2315678afecb367f032d93F642f64180aa3);
        assertEq(address(dvrFaucet), 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707);
        assertEq(address(usdc), 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853);
        assertEq(address(usdcFaucet), 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6);
        assertEq(address(clock), 0x9A676e781A523b5d0C0e43731313A708CB607508);
        assertEq(address(splitter), 0x0B306BF915C4d645ff596e518fAf3F9669b97016);
        assertEq(address(pool), 0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1);
        assertEq(splitter.pool(), address(pool));
        assertEq(address(pool.i_taxSplitter()), address(splitter));
        assertEq(pool.owner(), deployer);
        assertEq(pool.taxBps(), helper.INITIAL_TAX_BPS());
        assertEq(pool.reserveDvr(), helper.POOL_ALLOCATION());
        assertEq(pool.reserveUsdc(), helper.POOL_USDC());
        assertEq(token.balanceOf(address(pool)), helper.POOL_ALLOCATION());
        assertEq(usdc.balanceOf(address(pool)), helper.POOL_USDC());
        assertEq(token.balanceOf(address(dvrFaucet)), helper.FAUCET_ALLOCATION());
        assertEq(token.balanceOf(deployer), deployerDvr);
        assertEq(usdc.balanceOf(deployer), deployerUsdc);
        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(splitter)), 0);
        assertEq(token.allowance(deployer, address(pool)), 0);
        assertEq(usdc.allowance(deployer, address(pool)), 0);

        DemoDriverClock demo = DemoDriverClock(address(clock));
        assertEq(demo.owner(), deployer);
        assertEq(demo.offset(), 0);
        assertEq(demo.currentTime(), block.timestamp);

        vm.prank(deployer);
        demo.advanceTime(1 days);
        assertEq(demo.offset(), 1 days);
        assertEq(demo.currentTime(), block.timestamp + 1 days);
    }

    function test_SepoliaDeployUsesEnvDeployer() public {
        HelperConfig helper = new HelperConfig();
        address deployer = makeAddr("sepoliaDeployer");
        vm.setEnv("SEPOLIA_DEPLOYER", vm.toString(deployer));
        vm.chainId(helper.SEPOLIA_CHAIN_ID());
        DeployDriverToken.Deployed memory deployed = new DeployDriverToken().run();
        uint256 maxSupply = deployed.token.MAX_SUPPLY();
        _assertSeed(helper, deployer, deployed);
        assertEq(deployed.token.owner(), deployer);
        assertEq(deployed.token.totalMinted(), maxSupply);
        assertEq(deployed.token.totalSupply(), maxSupply);
        assertEq(deployed.token.balanceOf(address(deployed.dvrFaucet)), helper.FAUCET_ALLOCATION());
        assertEq(deployed.token.balanceOf(address(deployed.pool)), helper.POOL_ALLOCATION());
        assertEq(deployed.token.balanceOf(deployer), helper.COMMUNITY_ALLOCATION() + helper.TEAM_ALLOCATION());
        assertEq(deployed.pool.reserveDvr(), helper.POOL_ALLOCATION());
        assertEq(deployed.pool.reserveUsdc(), helper.POOL_USDC());
        assertEq(deployed.pool.taxBps(), helper.INITIAL_TAX_BPS());
        assertEq(deployed.splitter.pool(), address(deployed.pool));
        assertEq(address(deployed.dvrFaucet.i_token()), address(deployed.token));
        assertEq(deployed.dvrFaucet.i_claimAmount(), helper.DVR_FAUCET_CLAIM_AMOUNT());
        assertEq(deployed.dvrFaucet.i_claimCooldown(), helper.DVR_FAUCET_CLAIM_COOLDOWN());
        assertEq(deployed.dvrFaucet.i_dailyClaimLimit(), helper.DVR_FAUCET_DAILY_CLAIM_LIMIT());

        assertEq(deployed.usdc.owner(), deployer);
        assertEq(deployed.usdc.minter(), address(deployed.usdcFaucet));
        assertTrue(deployed.usdc.owner() != address(deployed.usdcFaucet));
        assertEq(deployed.usdc.decimals(), 6);
        assertEq(deployed.usdc.balanceOf(deployer), helper.FUND_3_USDC());
        assertEq(deployed.usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(deployed.usdc.balanceOf(address(deployed.pool)), helper.POOL_USDC());
        assertEq(deployed.usdc.balanceOf(address(deployed.usdcFaucet)), 0);
        assertEq(deployed.token.allowance(deployer, address(deployed.pool)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.pool)), 0);
        assertEq(address(deployed.usdcFaucet.i_usdc()), address(deployed.usdc));
        assertEq(deployed.usdcFaucet.i_claimAmount(), helper.USDC_FAUCET_CLAIM_AMOUNT());
        assertEq(deployed.usdcFaucet.i_claimCooldown(), helper.USDC_FAUCET_CLAIM_COOLDOWN());
        assertEq(deployed.usdcFaucet.i_dailyClaimLimit(), helper.USDC_FAUCET_DAILY_CLAIM_LIMIT());

        address user = makeAddr("user");
        vm.prank(user);
        deployed.dvrFaucet.claim();
        vm.prank(user);
        deployed.usdcFaucet.claim();
        assertEq(deployed.token.balanceOf(user), 10 * 10 ** 18);
        assertEq(deployed.token.balanceOf(address(deployed.dvrFaucet)), helper.FAUCET_ALLOCATION() - 10 * 10 ** 18);
        assertEq(deployed.token.totalMinted(), maxSupply);
        assertEq(deployed.usdc.balanceOf(user), 100 * 10 ** 6);
        assertEq(deployed.usdc.balanceOf(address(deployed.usdcFaucet)), 0);

        vm.expectRevert(
            abi.encodeWithSelector(DriverToken.DriverToken__LifetimeMintCapExceeded.selector, maxSupply, 1, maxSupply)
        );
        vm.prank(deployer);
        deployed.token.mint(deployer, 1);

        DriverClock production = DriverClock(address(deployed.clock));
        assertEq(production.currentTime(), block.timestamp);
        vm.warp(block.timestamp + 100);
        assertEq(production.currentTime(), block.timestamp);

        (bool ok, bytes memory data) = address(production).call(abi.encodeWithSignature("advanceTime(uint256)", 1));
        assertFalse(ok);
        assertEq(data.length, 0);
        assertEq(production.currentTime(), block.timestamp);
    }

    function test_AnvilDeployFundsTheFourFarms() public {
        HelperConfig helper = new HelperConfig();
        DeployDriverToken.Deployed memory deployed = new DeployDriverToken().run();
        MockUSDC usdc = deployed.usdc;
        IDriverClock clock = deployed.clock;
        MockFarm cruise = deployed.cruise;
        MockFarm highway = deployed.highway;
        MockFarm autobahn = deployed.autobahn;
        MockFarm drift = deployed.drift;
        address deployer = helper.ANVIL_DEPLOYER();
        _assertSeed(helper, deployer, deployed);

        assertEq(address(cruise), 0x59b670e9fA9D0A427751Af201D676719a970857b);
        assertEq(address(highway), 0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1);
        assertEq(address(autobahn), 0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44);
        assertEq(address(drift), 0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f);
        assertEq(address(deployed.schedule), 0xa82fF9aFd8f496c3d6ac40E2a0F282E47488CFc9);
        assertEq(address(deployed.cruiseControl), 0x1613beB3B2C4f22Ee086B2b38C1476A3cE7f78E8);
        assertEq(address(deployed.degenDriver), 0x851356ae760d987E095750cCeb3bC6014560891C);
        assertEq(address(deployed.vote), 0x1291Be112d480055DaFd8a610b7d1e203891C274);
        assertEq(deployed.cruiseControl.strategyCount(), 1);
        assertEq(address(deployed.cruiseControl.strategyAt(0)), address(cruise));
        assertEq(deployed.degenDriver.strategyCount(), 3);
        assertEq(address(deployed.degenDriver.strategyAt(0)), address(highway));
        assertEq(address(deployed.degenDriver.strategyAt(1)), address(autobahn));
        assertEq(address(deployed.degenDriver.strategyAt(2)), address(drift));
        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(deployer), helper.FUND_3_USDC());
        _assertFarms(helper, usdc, clock, deployer, cruise, highway, autobahn, drift);
    }

    function test_SepoliaDeployFundsTheFourFarms() public {
        HelperConfig helper = new HelperConfig();
        address deployer = makeAddr("sepoliaDeployer");
        vm.setEnv("SEPOLIA_DEPLOYER", vm.toString(deployer));
        vm.chainId(helper.SEPOLIA_CHAIN_ID());

        DeployDriverToken.Deployed memory deployed = new DeployDriverToken().run();
        MockUSDC usdc = deployed.usdc;
        IDriverClock clock = deployed.clock;
        MockFarm cruise = deployed.cruise;
        MockFarm highway = deployed.highway;
        MockFarm autobahn = deployed.autobahn;
        MockFarm drift = deployed.drift;
        _assertSeed(helper, deployer, deployed);

        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(deployer), helper.FUND_3_USDC());
        _assertFarms(helper, usdc, clock, deployer, cruise, highway, autobahn, drift);

        DriverClock production = DriverClock(address(clock));
        assertEq(production.currentTime(), block.timestamp);
        (bool ok, bytes memory data) = address(production).call(abi.encodeWithSignature("advanceTime(uint256)", 1));
        assertFalse(ok);
        assertEq(data.length, 0);
    }

    function _assertFarms(
        HelperConfig helper,
        MockUSDC usdc,
        IDriverClock clock,
        address deployer,
        MockFarm cruise,
        MockFarm highway,
        MockFarm autobahn,
        MockFarm drift
    ) private view {
        _assertFarm(cruise, usdc, clock, deployer, helper.CRUISE_APR_BPS(), helper.CRUISE_RESERVE());
        _assertFarm(highway, usdc, clock, deployer, helper.HIGHWAY_APR_BPS(), helper.HIGHWAY_RESERVE());
        _assertFarm(autobahn, usdc, clock, deployer, helper.AUTOBAHN_APR_BPS(), helper.AUTOBAHN_RESERVE());
        _assertFarm(drift, usdc, clock, deployer, helper.DRIFT_APR_BPS(), helper.DRIFT_RESERVE());
    }

    function _assertFarm(
        MockFarm farm,
        MockUSDC usdc,
        IDriverClock clock,
        address deployer,
        uint256 aprBps,
        uint256 reserve
    ) private view {
        assertEq(farm.aprBps(), aprBps);
        assertEq(address(farm.i_clock()), address(clock));
        assertEq(farm.owner(), deployer);
        assertEq(farm.rewardReserve(), reserve);
        assertFalse(farm.paused());
        assertFalse(farm.isDepositor(deployer));
        assertFalse(farm.isDepositor(address(0)));
        assertEq(usdc.allowance(deployer, address(farm)), 0);
    }

    function _assertSeed(HelperConfig helper, address deployer, DeployDriverToken.Deployed memory deployed)
        private
        view
    {
        assertEq(vm.getNonce(deployer), 52);
        assertEq(address(deployed.degenDriver.ballot()), address(deployed.vote));
        assertEq(address(deployed.vote.i_token()), address(deployed.token));
        assertEq(address(deployed.vote.i_schedule()), address(deployed.schedule));
        assertEq(address(deployed.vote.i_fund()), address(deployed.degenDriver));
        assertEq(deployed.vote.counted(), 0);
        assertEq(deployed.vote.locked(deployer), 0);
        assertEq(deployed.token.balanceOf(address(deployed.vote)), 0);
        assertEq(deployed.token.allowance(deployer, address(deployed.vote)), 0);
        assertEq(address(deployed.schedule.i_clock()), address(deployed.clock));
        assertEq(deployed.schedule.i_epoch(), helper.EPOCH_LENGTH());
        assertEq(deployed.schedule.i_start(), block.timestamp);
        assertEq(address(deployed.cruiseControl.i_schedule()), address(deployed.schedule));
        assertEq(address(deployed.degenDriver.i_schedule()), address(deployed.schedule));
        assertEq(deployed.cruiseControl.i_fund1Usdc(), helper.FUND_1_USDC());
        assertEq(deployed.cruiseControl.i_fund2Usdc(), helper.FUND_2_USDC());
        assertEq(deployed.degenDriver.i_fund1Usdc(), helper.FUND_1_USDC());
        assertEq(deployed.degenDriver.i_fund2Usdc(), helper.FUND_2_USDC());
        assertEq(address(deployed.degenDriver.i_fund1()), address(deployed.cruiseControl));
        assertEq(address(deployed.cruiseControl.fund2()), address(deployed.degenDriver));
        assertEq(deployed.usdc.allowance(address(deployed.cruiseControl), address(deployed.degenDriver)), 0);
        assertEq(deployed.usdc.allowance(address(deployed.degenDriver), address(deployed.cruiseControl)), 0);
        assertEq(deployed.token.balanceOf(deployer), helper.COMMUNITY_ALLOCATION() + helper.TEAM_ALLOCATION());
        assertEq(deployed.usdc.balanceOf(deployer), helper.FUND_3_USDC());
        assertEq(deployed.cruiseControl.idle(), 0);
        assertEq(deployed.cruiseControl.principal(), helper.FUND_1_USDC());
        assertEq(deployed.cruiseControl.value(), helper.FUND_1_USDC());
        assertEq(deployed.cruise.principalOf(address(deployed.cruiseControl)), helper.FUND_1_USDC());
        assertEq(deployed.cruise.totalPrincipal(), helper.FUND_1_USDC());
        assertEq(deployed.usdc.balanceOf(address(deployed.cruise)), helper.CRUISE_RESERVE() + helper.FUND_1_USDC());
        assertEq(deployed.degenDriver.idle(), helper.FUND_2_USDC());
        assertEq(deployed.degenDriver.principal(), 0);
        assertEq(deployed.degenDriver.value(), helper.FUND_2_USDC());
        assertEq(address(deployed.degenDriver.activeFarm()), address(0));
        (address cruiseExit, uint256 cruiseAmount, string memory cruiseReason) =
            deployed.cruiseControl.lastEmergencyExit();
        assertEq(cruiseExit, address(0));
        assertEq(cruiseAmount, 0);
        assertEq(bytes(cruiseReason).length, 0);
        (address degenExit, uint256 degenAmount, string memory degenReason) = deployed.degenDriver.lastEmergencyExit();
        assertEq(degenExit, address(0));
        assertEq(degenAmount, 0);
        assertEq(bytes(degenReason).length, 0);
        assertEq(deployed.highway.totalPrincipal(), 0);
        assertEq(deployed.autobahn.totalPrincipal(), 0);
        assertEq(deployed.drift.totalPrincipal(), 0);
        assertEq(deployed.highway.principalOf(address(deployed.degenDriver)), 0);
        assertEq(deployed.cruise.rewardReserve(), helper.CRUISE_RESERVE());
        assertEq(deployed.highway.rewardReserve(), helper.HIGHWAY_RESERVE());
        assertEq(deployed.autobahn.rewardReserve(), helper.AUTOBAHN_RESERVE());
        assertEq(deployed.drift.rewardReserve(), helper.DRIFT_RESERVE());
        assertEq(deployed.usdc.balanceOf(address(deployed.highway)), helper.HIGHWAY_RESERVE());
        assertEq(deployed.usdc.balanceOf(address(deployed.autobahn)), helper.AUTOBAHN_RESERVE());
        assertEq(deployed.usdc.balanceOf(address(deployed.drift)), helper.DRIFT_RESERVE());
        assertEq(deployed.token.allowance(deployer, address(deployed.pool)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.pool)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.cruise)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.highway)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.autobahn)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.drift)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.cruiseControl)), 0);
        assertEq(deployed.usdc.allowance(deployer, address(deployed.degenDriver)), 0);
        assertEq(deployed.usdc.allowance(address(deployed.cruiseControl), address(deployed.cruise)), 0);
        assertEq(deployed.usdc.allowance(address(deployed.degenDriver), address(deployed.highway)), 0);
        assertEq(deployed.usdc.allowance(address(deployed.degenDriver), address(deployed.autobahn)), 0);
        assertEq(deployed.usdc.allowance(address(deployed.degenDriver), address(deployed.drift)), 0);
        assertEq(deployed.splitter.recipient(TaxSplitter.FundId.Fund1), address(deployed.cruiseControl));
        assertEq(deployed.splitter.recipient(TaxSplitter.FundId.Fund2), address(deployed.degenDriver));
        assertEq(deployed.splitter.recipient(TaxSplitter.FundId.Fund3), address(0));
        assertTrue(deployed.cruise.isDepositor(address(deployed.cruiseControl)));
        assertTrue(deployed.highway.isDepositor(address(deployed.degenDriver)));
        assertTrue(deployed.autobahn.isDepositor(address(deployed.degenDriver)));
        assertTrue(deployed.drift.isDepositor(address(deployed.degenDriver)));
        assertFalse(deployed.cruise.isDepositor(deployer));
        assertFalse(deployed.highway.isDepositor(deployer));
        assertFalse(deployed.autobahn.isDepositor(deployer));
        assertFalse(deployed.drift.isDepositor(deployer));
        assertFalse(deployed.cruise.isDepositor(address(deployed.degenDriver)));
        assertFalse(deployed.highway.isDepositor(address(deployed.cruiseControl)));
        assertFalse(deployed.autobahn.isDepositor(address(deployed.cruiseControl)));
        assertFalse(deployed.drift.isDepositor(address(deployed.cruiseControl)));
    }
}
