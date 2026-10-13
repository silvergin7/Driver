// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract HelperConfigTest is Test {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;

    function test_AnvilConfigReturnsDefaultDeployer() public {
        HelperConfig helper = new HelperConfig();

        assertEq(block.chainid, helper.ANVIL_CHAIN_ID());
        assertEq(helper.getConfig().deployer, helper.ANVIL_DEPLOYER());
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

    function test_FaucetParametersMatchTheRules() public {
        HelperConfig helper = new HelperConfig();

        assertEq(helper.USDC_FAUCET_CLAIM_AMOUNT(), 100 * 10 ** 6);
        assertEq(helper.USDC_FAUCET_CLAIM_COOLDOWN(), 24 hours);
        assertEq(helper.USDC_FAUCET_DAILY_CLAIM_LIMIT(), 25);
    }

    function test_RevertWhen_ChainIsNotAnvil() public {
        vm.chainId(SEPOLIA_CHAIN_ID);
        HelperConfig helper = new HelperConfig();

        vm.expectRevert(abi.encodeWithSelector(HelperConfig.HelperConfig__ChainNotSupported.selector, SEPOLIA_CHAIN_ID));
        helper.getConfig();
    }
}
