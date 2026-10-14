// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract HelperConfigTest is Test {
    function test_AnvilConfigReturnsDefaultDeployer() public {
        HelperConfig helper = new HelperConfig();

        assertEq(block.chainid, helper.ANVIL_CHAIN_ID());
        assertEq(helper.getConfig().deployer, helper.ANVIL_DEPLOYER());
    }

    function test_AnvilConfigForReturnsDefaultDeployer() public {
        HelperConfig helper = new HelperConfig();

        assertEq(helper.configFor(helper.ANVIL_CHAIN_ID(), address(0)).deployer, helper.ANVIL_DEPLOYER());
        assertEq(
            helper.configFor(helper.ANVIL_CHAIN_ID(), makeAddr("sepoliaDeployer")).deployer, helper.ANVIL_DEPLOYER()
        );
    }

    function test_SepoliaConfigForReturnsGivenDeployer() public {
        HelperConfig helper = new HelperConfig();
        address sepoliaDeployer = makeAddr("sepoliaDeployer");

        assertEq(helper.configFor(helper.SEPOLIA_CHAIN_ID(), sepoliaDeployer).deployer, sepoliaDeployer);
    }

    function test_AnvilGetConfigIgnoresSepoliaEnv() public {
        address sepoliaDeployer = makeAddr("sepoliaDeployer");
        vm.setEnv("SEPOLIA_DEPLOYER", vm.toString(sepoliaDeployer));
        HelperConfig helper = new HelperConfig();

        assertEq(block.chainid, helper.ANVIL_CHAIN_ID());
        assertEq(helper.getConfig().deployer, helper.ANVIL_DEPLOYER());
    }

    function test_SepoliaGetConfigReturnsEnvDeployer() public {
        address sepoliaDeployer = makeAddr("sepoliaDeployer");
        vm.setEnv("SEPOLIA_DEPLOYER", vm.toString(sepoliaDeployer));
        vm.chainId(11_155_111);
        HelperConfig helper = new HelperConfig();

        assertEq(block.chainid, helper.SEPOLIA_CHAIN_ID());
        assertEq(helper.getConfig().deployer, sepoliaDeployer);
    }

    function test_AllocationConstantsSumToMaxSupply() public {
        HelperConfig helper = new HelperConfig();
        DriverToken token = new DriverToken(helper.ANVIL_DEPLOYER());

        assertEq(
            helper.POOL_ALLOCATION() + helper.FAUCET_ALLOCATION() + helper.COMMUNITY_ALLOCATION()
                + helper.TEAM_ALLOCATION(),
            token.MAX_SUPPLY()
        );
    }

    function test_UsdcSetupAmountsUseSixDecimals() public {
        HelperConfig helper = new HelperConfig();

        assertEq(helper.POOL_USDC(), 10_000 * 10 ** 6);
        assertEq(helper.FUND_1_USDC(), 15_000 * 10 ** 6);
        assertEq(helper.FUND_2_USDC(), 5_000 * 10 ** 6);
        assertEq(helper.FUND_3_USDC(), 5_000 * 10 ** 6);
        assertEq(
            helper.POOL_USDC() + helper.FUND_1_USDC() + helper.FUND_2_USDC() + helper.FUND_3_USDC(), 35_000 * 10 ** 6
        );
    }

    function test_DvrFaucetParametersMatchTheRules() public {
        HelperConfig helper = new HelperConfig();

        assertEq(helper.DVR_FAUCET_CLAIM_AMOUNT(), 10 * 10 ** 18);
        assertEq(helper.DVR_FAUCET_CLAIM_COOLDOWN(), 24 hours);
        assertEq(helper.DVR_FAUCET_DAILY_CLAIM_LIMIT(), 25);
        assertEq(helper.FAUCET_ALLOCATION() / helper.DVR_FAUCET_CLAIM_AMOUNT(), 5_000);
    }

    function test_FaucetParametersMatchTheRules() public {
        HelperConfig helper = new HelperConfig();

        assertEq(helper.USDC_FAUCET_CLAIM_AMOUNT(), 100 * 10 ** 6);
        assertEq(helper.USDC_FAUCET_CLAIM_COOLDOWN(), 24 hours);
        assertEq(helper.USDC_FAUCET_DAILY_CLAIM_LIMIT(), 25);
    }

    function test_RevertWhen_SepoliaDeployerIsZero() public {
        HelperConfig helper = new HelperConfig();
        uint256 sepoliaChainId = helper.SEPOLIA_CHAIN_ID();

        vm.expectRevert(HelperConfig.HelperConfig__SepoliaDeployerNotSet.selector);
        helper.configFor(sepoliaChainId, address(0));
    }

    function test_RevertWhen_ChainIsNotConfigured() public {
        HelperConfig helper = new HelperConfig();

        vm.expectRevert(abi.encodeWithSelector(HelperConfig.HelperConfig__ChainNotSupported.selector, 1));
        helper.configFor(1, address(0));
    }
}
