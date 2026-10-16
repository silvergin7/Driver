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
        (
            DriverToken token,
            DriverFaucet dvrFaucet,,,,,
            OfficialPool pool,
            MockFarm cruise,
            MockFarm highway,
            MockFarm autobahn,
            MockFarm drift
        ) = new DeployDriverToken().run();
        assertEq(
            cruise.totalPrincipal() + highway.totalPrincipal() + autobahn.totalPrincipal() + drift.totalPrincipal(), 0
        );
        address deployer = helper.ANVIL_DEPLOYER();
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
        (
            ,,
            MockUSDC usdc,
            MockUsdcFaucet faucet,,,
            OfficialPool pool,
            MockFarm cruise,
            MockFarm highway,
            MockFarm autobahn,
            MockFarm drift
        ) = new DeployDriverToken().run();
        address deployer = helper.ANVIL_DEPLOYER();
        uint256 deployerBalance = helper.FUND_1_USDC() + helper.FUND_2_USDC() + helper.FUND_3_USDC();

        assertEq(usdc.owner(), deployer);
        assertEq(usdc.minter(), address(faucet));
        assertTrue(usdc.owner() != address(faucet));
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(cruise)), helper.CRUISE_RESERVE());
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
        uint256 deployerUsdc = helper.FUND_1_USDC() + helper.FUND_2_USDC() + helper.FUND_3_USDC();
        (
            DriverToken token,
            DriverFaucet dvrFaucet,
            MockUSDC usdc,
            MockUsdcFaucet usdcFaucet,
            IDriverClock clock,
            TaxSplitter splitter,
            OfficialPool pool,,,,
        ) = new DeployDriverToken().run();
        address deployer = helper.ANVIL_DEPLOYER();

        assertEq(vm.getNonce(deployer), 34);
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
        uint256 deployerDvr = helper.COMMUNITY_ALLOCATION() + helper.TEAM_ALLOCATION();
        uint256 deployerUsdc = helper.FUND_1_USDC() + helper.FUND_2_USDC() + helper.FUND_3_USDC();

        (
            DriverToken token,
            DriverFaucet dvrFaucet,
            MockUSDC usdc,
            MockUsdcFaucet faucet,
            IDriverClock clock,
            TaxSplitter splitter,
            OfficialPool pool,,,,
        ) = new DeployDriverToken().run();
        uint256 maxSupply = token.MAX_SUPPLY();

        assertEq(vm.getNonce(deployer), 34);
        assertEq(token.owner(), deployer);
        assertEq(token.totalMinted(), maxSupply);
        assertEq(token.totalSupply(), maxSupply);
        assertEq(token.balanceOf(address(dvrFaucet)), helper.FAUCET_ALLOCATION());
        assertEq(token.balanceOf(address(pool)), helper.POOL_ALLOCATION());
        assertEq(token.balanceOf(deployer), deployerDvr);
        assertEq(pool.reserveDvr(), helper.POOL_ALLOCATION());
        assertEq(pool.reserveUsdc(), helper.POOL_USDC());
        assertEq(pool.taxBps(), helper.INITIAL_TAX_BPS());
        assertEq(splitter.pool(), address(pool));
        assertEq(address(dvrFaucet.i_token()), address(token));
        assertEq(dvrFaucet.i_claimAmount(), helper.DVR_FAUCET_CLAIM_AMOUNT());
        assertEq(dvrFaucet.i_claimCooldown(), helper.DVR_FAUCET_CLAIM_COOLDOWN());
        assertEq(dvrFaucet.i_dailyClaimLimit(), helper.DVR_FAUCET_DAILY_CLAIM_LIMIT());

        assertEq(usdc.owner(), deployer);
        assertEq(usdc.minter(), address(faucet));
        assertTrue(usdc.owner() != address(faucet));
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.balanceOf(deployer), deployerUsdc);
        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(address(pool)), helper.POOL_USDC());
        assertEq(usdc.balanceOf(address(faucet)), 0);
        assertEq(token.allowance(deployer, address(pool)), 0);
        assertEq(usdc.allowance(deployer, address(pool)), 0);
        assertEq(address(faucet.i_usdc()), address(usdc));
        assertEq(faucet.i_claimAmount(), helper.USDC_FAUCET_CLAIM_AMOUNT());
        assertEq(faucet.i_claimCooldown(), helper.USDC_FAUCET_CLAIM_COOLDOWN());
        assertEq(faucet.i_dailyClaimLimit(), helper.USDC_FAUCET_DAILY_CLAIM_LIMIT());

        address user = makeAddr("user");
        vm.prank(user);
        dvrFaucet.claim();
        vm.prank(user);
        faucet.claim();
        assertEq(token.balanceOf(user), 10 * 10 ** 18);
        assertEq(token.balanceOf(address(dvrFaucet)), helper.FAUCET_ALLOCATION() - 10 * 10 ** 18);
        assertEq(token.totalMinted(), maxSupply);
        assertEq(usdc.balanceOf(user), 100 * 10 ** 6);
        assertEq(usdc.balanceOf(address(faucet)), 0);

        vm.expectRevert(
            abi.encodeWithSelector(DriverToken.DriverToken__LifetimeMintCapExceeded.selector, maxSupply, 1, maxSupply)
        );
        vm.prank(deployer);
        token.mint(deployer, 1);

        DriverClock production = DriverClock(address(clock));
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
        (
            ,,
            MockUSDC usdc,,
            IDriverClock clock,,,
            MockFarm cruise,
            MockFarm highway,
            MockFarm autobahn,
            MockFarm drift
        ) = new DeployDriverToken().run();
        address deployer = helper.ANVIL_DEPLOYER();

        assertEq(vm.getNonce(deployer), 34);
        assertEq(address(cruise), 0x59b670e9fA9D0A427751Af201D676719a970857b);
        assertEq(address(highway), 0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1);
        assertEq(address(autobahn), 0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44);
        assertEq(address(drift), 0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f);
        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(deployer), 25_000 * 10 ** 6);
        _assertFarms(helper, usdc, clock, deployer, cruise, highway, autobahn, drift);
    }

    function test_SepoliaDeployFundsTheFourFarms() public {
        HelperConfig helper = new HelperConfig();
        address deployer = makeAddr("sepoliaDeployer");
        vm.setEnv("SEPOLIA_DEPLOYER", vm.toString(deployer));
        vm.chainId(helper.SEPOLIA_CHAIN_ID());

        (
            ,,
            MockUSDC usdc,,
            IDriverClock clock,,,
            MockFarm cruise,
            MockFarm highway,
            MockFarm autobahn,
            MockFarm drift
        ) = new DeployDriverToken().run();

        assertEq(vm.getNonce(deployer), 34);
        assertEq(usdc.totalSupply(), 170_000 * 10 ** 6);
        assertEq(usdc.balanceOf(deployer), 25_000 * 10 ** 6);
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
        assertEq(farm.totalPrincipal(), 0);
        assertFalse(farm.isDepositor(deployer));
        assertFalse(farm.isDepositor(address(0)));
        assertEq(usdc.allowance(deployer, address(farm)), 0);
        assertEq(usdc.balanceOf(address(farm)), reserve);
    }
}
