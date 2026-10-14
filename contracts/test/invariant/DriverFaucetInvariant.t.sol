// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverFaucet} from "../../src/DriverFaucet.sol";
import {DriverFaucetHandler} from "./handlers/DriverFaucetHandler.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DriverFaucetInvariantTest is Test {
    uint256 internal constant ACTORS = 400;

    DriverToken internal token;
    DriverFaucet internal faucet;
    DriverFaucetHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        HelperConfig helper = new HelperConfig();
        token = new DriverToken(owner);
        faucet = new DriverFaucet(
            token,
            helper.DVR_FAUCET_CLAIM_AMOUNT(),
            helper.DVR_FAUCET_CLAIM_COOLDOWN(),
            helper.DVR_FAUCET_DAILY_CLAIM_LIMIT()
        );
        vm.startPrank(owner);
        token.mint(owner, helper.FAUCET_ALLOCATION());
        assertTrue(token.transfer(address(faucet), helper.FAUCET_ALLOCATION()));
        vm.stopPrank();

        address[] memory actors = new address[](ACTORS);
        for (uint256 i = 0; i < actors.length; i++) {
            actors[i] = makeAddr(string(abi.encodePacked("actor", i)));
        }

        handler = new DriverFaucetHandler(token, faucet, actors);
        excludeContract(address(token));
        excludeContract(address(faucet));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.claim.selector;
        selectors[1] = handler.claimBurst.selector;
        selectors[2] = handler.warpForward.selector;
        selectors[3] = handler.transfer.selector;
        selectors[4] = handler.claimAfterCooldown.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_PaidSumMatchesFaucetBalanceDrop() public view {
        assertEq(handler.s_initialFaucetBalance() - token.balanceOf(address(faucet)), handler.s_ghostPaidSum());
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

    function invariant_TotalSupplyDoesNotChange() public view {
        assertEq(token.totalSupply(), handler.s_initialSupply());
    }

    function afterInvariant() public view {
        assertGt(handler.s_ghostDailyLimitHits(), 0);
        assertGt(handler.s_ghostRepeatClaims(), 0);
    }
}
