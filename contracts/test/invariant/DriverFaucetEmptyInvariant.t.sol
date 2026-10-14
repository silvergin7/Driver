// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverFaucet} from "../../src/DriverFaucet.sol";
import {DriverFaucetEmptyHandler} from "./handlers/DriverFaucetEmptyHandler.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

/// forge-config: default.invariant.depth = 20
contract DriverFaucetEmptyInvariantTest is Test {
    uint256 internal constant ACTORS = 400;

    DriverToken internal token;
    DriverFaucet internal faucet;
    DriverFaucetEmptyHandler internal handler;

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
        uint256 funding = faucet.i_dailyClaimLimit() * faucet.i_claimAmount();
        vm.startPrank(owner);
        token.mint(owner, funding);
        assertTrue(token.transfer(address(faucet), funding));
        vm.stopPrank();

        address[] memory actors = new address[](ACTORS);
        for (uint256 i = 0; i < actors.length; i++) {
            actors[i] = makeAddr(string(abi.encodePacked("actor", i)));
        }

        handler = new DriverFaucetEmptyHandler(token, faucet, actors);
        excludeContract(address(token));
        excludeContract(address(faucet));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.claimBurst.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_PaidSumMatchesFaucetBalanceDrop() public view {
        assertEq(handler.s_initialFaucetBalance() - token.balanceOf(address(faucet)), handler.s_ghostPaidSum());
    }

    function invariant_PaidSumDoesNotExceedInitialBalance() public view {
        assertLe(handler.s_ghostPaidSum(), handler.s_initialFaucetBalance());
    }

    function invariant_TotalSupplyDoesNotChange() public view {
        assertEq(token.totalSupply(), handler.s_initialSupply());
    }

    function afterInvariant() public view {
        assertGt(handler.s_ghostInsufficientBalanceHits(), 0);
    }
}
