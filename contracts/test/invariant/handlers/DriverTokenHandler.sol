// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../../src/DriverToken.sol";

contract DriverTokenHandler is Test {
    DriverToken internal immutable i_token;
    address internal immutable i_owner;
    address[] internal s_holders;
    uint256 public s_ghostMintedSum;

    constructor(DriverToken token, address owner_, address[] memory holders) {
        i_token = token;
        i_owner = owner_;
        uint256 length = holders.length;
        for (uint256 i = 0; i < length; i++) {
            s_holders.push(holders[i]);
        }
    }

    function mint(uint256 amount, uint256 holderSeed) external {
        uint256 remaining = i_token.MAX_SUPPLY() - i_token.totalMinted();
        if (remaining == 0) return;

        amount = bound(amount, 1, remaining);
        address to = s_holders[holderSeed % s_holders.length];

        vm.prank(i_owner);
        i_token.mint(to, amount);
        s_ghostMintedSum += amount;
    }

    function burn(uint256 amount, uint256 holderSeed) external {
        address holder = s_holders[holderSeed % s_holders.length];
        uint256 balance = i_token.balanceOf(holder);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);
        vm.prank(holder);
        i_token.burn(amount);
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
