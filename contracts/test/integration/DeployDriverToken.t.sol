// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverFaucet} from "../../src/DriverFaucet.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../../src/MockUsdcFaucet.sol";
import {DeployDriverToken} from "../../script/DeployDriverToken.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DeployDriverTokenTest is Test {
    function test_AnvilDeployMintsFullSupplyAndFundsFaucet() public {
        HelperConfig helper = new HelperConfig();
        (DriverToken token, DriverFaucet dvrFaucet,,) = new DeployDriverToken().run();
        address deployer = helper.ANVIL_DEPLOYER();
        uint256 maxSupply = token.MAX_SUPPLY();

        assertEq(token.owner(), deployer);
        assertEq(token.totalMinted(), maxSupply);
        assertEq(token.totalSupply(), maxSupply);
        assertEq(token.balanceOf(address(dvrFaucet)), helper.FAUCET_ALLOCATION());
        assertEq(token.balanceOf(deployer), maxSupply - helper.FAUCET_ALLOCATION());
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
        (,, MockUSDC usdc, MockUsdcFaucet faucet) = new DeployDriverToken().run();
        address deployer = helper.ANVIL_DEPLOYER();
        uint256 setupBalance = 35_000 * 10 ** 6;

        assertEq(usdc.owner(), deployer);
        assertEq(usdc.minter(), address(faucet));
        assertTrue(usdc.owner() != address(faucet));
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.balanceOf(deployer), setupBalance);
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
        assertEq(usdc.balanceOf(deployer), setupBalance + 1);
    }
}
