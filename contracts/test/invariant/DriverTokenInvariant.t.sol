// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverTokenHandler} from "./handlers/DriverTokenHandler.sol";

contract DriverTokenInvariantTest is Test {
    DriverToken internal token;
    DriverTokenHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        token = new DriverToken(owner);

        address[] memory holders = new address[](3);
        holders[0] = makeAddr("alice");
        holders[1] = makeAddr("bob");
        holders[2] = makeAddr("carol");

        handler = new DriverTokenHandler(token, owner, holders);
        excludeContract(address(token));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.mint.selector;
        selectors[1] = handler.burn.selector;
        selectors[2] = handler.transfer.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalMintedDoesNotExceedMaxSupply() public view {
        assertLe(token.totalMinted(), token.MAX_SUPPLY());
    }

    function invariant_TotalSupplyDoesNotExceedTotalMinted() public view {
        assertLe(token.totalSupply(), token.totalMinted());
    }

    function invariant_TotalMintedDoesNotDecrease() public view {
        assertEq(token.totalMinted(), handler.s_ghostMintedSum());
    }
}
