// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DriverToken} from "../../src/DriverToken.sol";

contract DriverTokenFuzzTest is Test {
    DriverToken internal token;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new DriverToken(owner);
    }

    function testFuzz_MintWithinRemainingCap(uint256 first, uint256 second) public {
        first = bound(first, 1, token.MAX_SUPPLY());
        second = bound(second, 0, token.MAX_SUPPLY() - first);

        vm.startPrank(owner);
        token.mint(alice, first);
        if (second > 0) {
            token.mint(bob, second);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), second);
        assertEq(token.totalSupply(), first + second);
        assertEq(token.totalMinted(), first + second);
    }

    function testFuzz_RevertWhen_MintExceedsRemainingCap(uint256 already, uint256 extra) public {
        already = bound(already, 0, token.MAX_SUPPLY());
        uint256 remaining = token.MAX_SUPPLY() - already;
        extra = bound(extra, remaining + 1, type(uint256).max);

        if (already > 0) {
            vm.prank(owner);
            token.mint(alice, already);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                DriverToken.DriverToken__LifetimeMintCapExceeded.selector, already, extra, token.MAX_SUPPLY()
            )
        );
        vm.prank(owner);
        token.mint(alice, extra);

        assertEq(token.totalMinted(), already);
        assertEq(token.totalSupply(), already);
    }

    function testFuzz_BurnDoesNotDecreaseTotalMinted(uint256 minted, uint256 burned) public {
        minted = bound(minted, 1, token.MAX_SUPPLY());
        burned = bound(burned, 1, minted);

        vm.prank(owner);
        token.mint(alice, minted);
        vm.prank(alice);
        token.burn(burned);

        assertEq(token.totalMinted(), minted);
        assertEq(token.totalSupply(), minted - burned);
        assertEq(token.balanceOf(alice), minted - burned);
    }

    function testFuzz_TransferConservesSupply(uint256 minted, uint256 sent) public {
        minted = bound(minted, 1, token.MAX_SUPPLY());
        sent = bound(sent, 0, minted);

        vm.prank(owner);
        token.mint(alice, minted);
        vm.prank(alice);
        assertTrue(token.transfer(bob, sent));

        assertEq(token.totalSupply(), minted);
        assertEq(token.totalMinted(), minted);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), minted);
    }
}
