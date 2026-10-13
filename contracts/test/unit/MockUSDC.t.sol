// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";

contract MockUSDCTest is Test, IERC20Errors {
    uint256 internal constant ONE_TOKEN = 1_000_000;

    MockUSDC internal token;
    address internal owner = makeAddr("owner");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event Minted(address indexed to, uint256 amount);
    event MinterUpdated(address indexed previous, address indexed newMinter);

    function setUp() public {
        token = new MockUSDC(owner);
    }

    function test_ConstructorSetsNameSymbolDecimalsAndOwner() public view {
        assertEq(token.name(), "Mock USDC");
        assertEq(token.symbol(), "mUSDC");
        assertEq(token.decimals(), 6);
        assertEq(token.owner(), owner);
    }

    function test_ConstructorMintsNothing() public view {
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.minter(), address(0));
    }

    function test_OwnerMintUpdatesBalanceAndSupply() public {
        _mint(alice, ONE_TOKEN);

        assertEq(token.balanceOf(alice), ONE_TOKEN);
        assertEq(token.totalSupply(), ONE_TOKEN);
    }

    function test_OwnerMintEmitsMintedAndTransfer() public {
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(0), alice, ONE_TOKEN);
        vm.expectEmit(address(token));
        emit Minted(alice, ONE_TOKEN);

        _mint(alice, ONE_TOKEN);
    }

    function test_FaucetMintUpdatesBalanceAndSupply() public {
        _setMinter(minter);
        _mintFromFaucet(alice, ONE_TOKEN);

        assertEq(token.balanceOf(alice), ONE_TOKEN);
        assertEq(token.totalSupply(), ONE_TOKEN);
    }

    function test_FaucetMintEmitsMintedAndTransfer() public {
        _setMinter(minter);

        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(0), alice, ONE_TOKEN);
        vm.expectEmit(address(token));
        emit Minted(alice, ONE_TOKEN);

        _mintFromFaucet(alice, ONE_TOKEN);
    }

    function test_SetMinterEmitsMinterUpdated() public {
        vm.expectEmit(address(token));
        emit MinterUpdated(address(0), minter);

        _setMinter(minter);

        assertEq(token.minter(), minter);

        vm.expectEmit(address(token));
        emit MinterUpdated(minter, bob);

        _setMinter(bob);

        assertEq(token.minter(), bob);
    }

    function test_OneWholeTokenIsOneMillionBaseUnits() public {
        assertEq(10 ** token.decimals(), ONE_TOKEN);

        _mint(alice, 10 ** token.decimals());

        assertEq(token.balanceOf(alice), ONE_TOKEN);
    }

    function test_TransferMovesTokens() public {
        _mint(alice, 10 * ONE_TOKEN);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 4 * ONE_TOKEN));

        assertEq(token.balanceOf(alice), 6 * ONE_TOKEN);
        assertEq(token.balanceOf(bob), 4 * ONE_TOKEN);
        assertEq(token.totalSupply(), 10 * ONE_TOKEN);
    }

    function test_TransferFromMovesTokens() public {
        _mint(alice, 10 * ONE_TOKEN);

        vm.prank(alice);
        token.approve(bob, 4 * ONE_TOKEN);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 4 * ONE_TOKEN));

        assertEq(token.balanceOf(alice), 6 * ONE_TOKEN);
        assertEq(token.balanceOf(bob), 4 * ONE_TOKEN);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), 10 * ONE_TOKEN);
    }

    function test_OwnershipTransfersOnlyAfterAcceptance() public {
        address next = makeAddr("next");
        _setMinter(minter);

        vm.prank(owner);
        token.transferOwnership(next);

        assertEq(token.owner(), owner);
        assertEq(token.pendingOwner(), next);
        assertEq(token.minter(), minter);

        vm.prank(next);
        token.acceptOwnership();

        assertEq(token.owner(), next);
        assertEq(token.pendingOwner(), address(0));
        assertEq(token.minter(), minter);

        vm.prank(next);
        token.mint(alice, ONE_TOKEN);
        assertEq(token.balanceOf(alice), ONE_TOKEN);

        vm.prank(next);
        token.setMinter(bob);
        assertEq(token.minter(), bob);
    }

    function test_MinterIsNotOwner() public {
        _setMinter(minter);

        assertEq(token.owner(), owner);
        assertEq(token.minter(), minter);
        assertTrue(token.minter() != token.owner());
    }

    function test_RevertWhen_OwnerMintCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.mint(alice, ONE_TOKEN);

        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_SetMinterCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.setMinter(alice);

        assertEq(token.minter(), address(0));
    }

    function test_RevertWhen_FaucetMintCallerIsNotMinter() public {
        _setMinter(minter);

        vm.expectRevert(abi.encodeWithSelector(MockUSDC.MockUSDC__CallerNotMinter.selector, alice));
        vm.prank(alice);
        token.mintFromFaucet(alice, ONE_TOKEN);

        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_OwnerCallsFaucetMint() public {
        vm.expectRevert(abi.encodeWithSelector(MockUSDC.MockUSDC__CallerNotMinter.selector, owner));
        vm.prank(owner);
        token.mintFromFaucet(alice, ONE_TOKEN);

        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_MinterCallsOwnerMint() public {
        _setMinter(minter);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, minter));
        vm.prank(minter);
        token.mint(alice, ONE_TOKEN);

        assertEq(token.totalSupply(), 0);
    }

    function test_ClearingMinterBlocksFaucetMint() public {
        _setMinter(minter);
        _mintFromFaucet(alice, ONE_TOKEN);

        _setMinter(address(0));

        vm.expectRevert(abi.encodeWithSelector(MockUSDC.MockUSDC__CallerNotMinter.selector, minter));
        vm.prank(minter);
        token.mintFromFaucet(alice, ONE_TOKEN);

        _mint(bob, ONE_TOKEN);

        assertEq(token.minter(), address(0));
        assertEq(token.balanceOf(alice), ONE_TOKEN);
        assertEq(token.balanceOf(bob), ONE_TOKEN);
        assertEq(token.totalSupply(), 2 * ONE_TOKEN);
    }

    function test_RevertWhen_OwnerMintToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0)));
        _mint(address(0), ONE_TOKEN);

        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_FaucetMintToZeroAddress() public {
        _setMinter(minter);

        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0)));
        _mintFromFaucet(address(0), ONE_TOKEN);

        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_OwnerMintAmountIsZero() public {
        vm.expectRevert(MockUSDC.MockUSDC__ZeroAmount.selector);
        _mint(alice, 0);

        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_FaucetMintAmountIsZero() public {
        _setMinter(minter);

        vm.expectRevert(MockUSDC.MockUSDC__ZeroAmount.selector);
        _mintFromFaucet(alice, 0);

        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_InitialOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new MockUSDC(address(0));
    }

    function _mint(address to, uint256 amount) internal {
        vm.prank(owner);
        token.mint(to, amount);
    }

    function _mintFromFaucet(address to, uint256 amount) internal {
        vm.prank(minter);
        token.mintFromFaucet(to, amount);
    }

    function _setMinter(address account) internal {
        vm.prank(owner);
        token.setMinter(account);
    }
}
