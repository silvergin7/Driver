// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {MockUSDCHandler} from "./handlers/MockUSDCHandler.sol";

contract MockUSDCInvariantTest is Test {
    MockUSDC internal token;
    MockUSDCHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        address minter = makeAddr("minter");
        token = new MockUSDC(owner);
        vm.prank(owner);
        token.setMinter(minter);

        address[] memory holders = new address[](3);
        holders[0] = makeAddr("alice");
        holders[1] = makeAddr("bob");
        holders[2] = makeAddr("carol");

        handler = new MockUSDCHandler(token, owner, minter, holders);
        excludeContract(address(token));
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.ownerMint.selector;
        selectors[1] = handler.mintFromFaucet.selector;
        selectors[2] = handler.transfer.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyEqualsGhostMintedSum() public view {
        assertEq(token.totalSupply(), handler.s_ghostMintedSum());
    }
}
