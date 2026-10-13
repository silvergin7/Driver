// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../../src/MockUSDC.sol";

contract MockUSDCHandler is Test {
    MockUSDC internal immutable i_token;
    address internal immutable i_owner;
    address internal immutable i_minter;
    address[] internal s_holders;
    uint256 public s_ghostMintedSum;

    constructor(MockUSDC token, address owner_, address minter_, address[] memory holders) {
        i_token = token;
        i_owner = owner_;
        i_minter = minter_;
        uint256 length = holders.length;
        for (uint256 i = 0; i < length; i++) {
            s_holders.push(holders[i]);
        }
    }

    function ownerMint(uint256 amount, uint256 holderSeed) external {
        amount = bound(amount, 1, 1e12 * 10 ** 6);
        address to = s_holders[holderSeed % s_holders.length];

        vm.prank(i_owner);
        i_token.mint(to, amount);
        s_ghostMintedSum += amount;
    }

    function mintFromFaucet(uint256 amount, uint256 holderSeed) external {
        amount = bound(amount, 1, 1e12 * 10 ** 6);
        address to = s_holders[holderSeed % s_holders.length];

        vm.prank(i_minter);
        i_token.mintFromFaucet(to, amount);
        s_ghostMintedSum += amount;
    }

    function transfer(uint256 amount, uint256 fromSeed, uint256 toSeed) external {
        address from = s_holders[fromSeed % s_holders.length];
        address to = s_holders[toSeed % s_holders.length];
        uint256 balance = i_token.balanceOf(from);
        if (balance == 0) return;

        amount = bound(amount, 0, balance);
        vm.prank(from);
        assertTrue(i_token.transfer(to, amount));
    }
}
