// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";

contract MockUSDCFuzzTest is Test {
    MockUSDC internal token;
    address internal owner = makeAddr("owner");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new MockUSDC(owner);
        vm.prank(owner);
        token.setMinter(minter);
    }

    function testFuzz_OwnerMintIncreasesSupplyByAmount(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(owner);
        token.mint(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testFuzz_FaucetMintIncreasesSupplyByAmount(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(minter);
        token.mintFromFaucet(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testFuzz_TransferConservesSupply(uint256 minted, uint256 sent) public {
        minted = bound(minted, 1, 1e12 * 10 ** 6);
        sent = bound(sent, 0, minted);

        vm.prank(owner);
        token.mint(alice, minted);
        vm.prank(alice);
        assertTrue(token.transfer(bob, sent));

        assertEq(token.totalSupply(), minted);
        assertEq(token.balanceOf(alice), minted - sent);
        assertEq(token.balanceOf(bob), sent);
    }
}
