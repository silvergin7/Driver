// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {MockUsdcFaucet} from "../../src/MockUsdcFaucet.sol";
import {MockUsdcFaucetHandler} from "./handlers/MockUsdcFaucetHandler.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract MockUsdcFaucetInvariantTest is Test {
    uint256 internal constant ACTORS = 400;

    MockUSDC internal token;
    MockUsdcFaucet internal faucet;
    MockUsdcFaucetHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        HelperConfig helper = new HelperConfig();
        token = new MockUSDC(owner);
        faucet = new MockUsdcFaucet(
            token,
            helper.USDC_FAUCET_CLAIM_AMOUNT(),
            helper.USDC_FAUCET_CLAIM_COOLDOWN(),
            helper.USDC_FAUCET_DAILY_CLAIM_LIMIT()
        );
        vm.prank(owner);
        token.setMinter(address(faucet));

        address[] memory actors = new address[](ACTORS);
        for (uint256 i = 0; i < actors.length; i++) {
            actors[i] = makeAddr(string(abi.encodePacked("actor", i)));
        }

        handler = new MockUsdcFaucetHandler(token, faucet, owner, actors);
        excludeContract(address(token));
        excludeContract(address(faucet));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.ownerMint.selector;
        selectors[1] = handler.claim.selector;
        selectors[2] = handler.transfer.selector;
        selectors[3] = handler.warpForward.selector;
        selectors[4] = handler.claimBurst.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyEqualsGhostMintedSum() public view {
        assertEq(token.totalSupply(), handler.s_ghostMintedSum());
    }

    function invariant_ClaimsPerUtcDayDoNotExceedLimit() public view {
        assertLe(handler.s_ghostClaimsPerDay(handler.s_ghostBusiestDay()), faucet.i_dailyClaimLimit());
    }

    function invariant_WalletClaimsAreAtLeastOneCooldownApart() public view {
        uint256 gap = handler.s_ghostMinRepeatGap();
        if (gap != type(uint256).max) {
            assertGe(gap, faucet.i_claimCooldown());
        }
    }

    function afterInvariant() public view {
        assertGt(handler.s_ghostDailyLimitHits(), 0);
    }
}
