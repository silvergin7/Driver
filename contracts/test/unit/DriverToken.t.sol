// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DriverToken} from "../../src/DriverToken.sol";

contract DriverTokenTest is Test, IERC20Errors {
    DriverToken internal token;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event Minted(address indexed to, uint256 amount);

    function setUp() public {
        token = new DriverToken(owner);
    }

    function test_ConstructorSetsNameSymbolDecimalsAndOwner() public view {
        assertEq(token.name(), "Driver");
        assertEq(token.symbol(), "DVR");
        assertEq(token.decimals(), 18);
        assertEq(token.owner(), owner);
    }

    function test_ConstructorMintsNothing() public view {
        assertEq(token.totalSupply(), 0);
        assertEq(token.totalMinted(), 0);
        assertEq(token.balanceOf(owner), 0);
    }

    function test_MintUpdatesBalanceSupplyAndTotalMinted() public {
        uint256 amount = 1_000 ether;

        _mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), amount);
        assertEq(token.totalMinted(), amount);
    }

    function test_MintEmitsMintedAndTransfer() public {
        uint256 amount = 1_000 ether;

        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(0), alice, amount);
        vm.expectEmit(address(token));
        emit Minted(alice, amount);

        _mint(alice, amount);
    }

    function test_MintExactCapSucceeds() public {
        _mint(alice, token.MAX_SUPPLY());

        assertEq(token.totalMinted(), token.MAX_SUPPLY());
        assertEq(token.totalSupply(), token.MAX_SUPPLY());
        assertEq(token.balanceOf(alice), token.MAX_SUPPLY());
    }

    function test_RepeatedMintsReachTheCap() public {
        uint256 half = token.MAX_SUPPLY() / 2;

        _mint(alice, half);
        _mint(bob, half);

        assertEq(token.totalMinted(), token.MAX_SUPPLY());
        assertEq(token.totalSupply(), token.MAX_SUPPLY());

        _expectLifetimeCap(token.MAX_SUPPLY(), 1);
        _mint(alice, 1);
    }

    function test_BurnReducesBalanceAndSupply() public {
        _mint(alice, 10 ether);

        vm.prank(alice);
        token.burn(4 ether);

        assertEq(token.balanceOf(alice), 6 ether);
        assertEq(token.totalSupply(), 6 ether);
    }

    function test_BurnLeavesTotalMintedUnchanged() public {
        _mint(alice, 10 ether);

        vm.prank(alice);
        token.burn(10 ether);

        assertEq(token.totalSupply(), 0);
        assertEq(token.totalMinted(), 10 ether);
    }

    function test_BurnFromSpendsAllowanceAndLeavesTotalMintedUnchanged() public {
        _mint(alice, 25 ether);

        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        token.burnFrom(alice, 10 ether);

        assertEq(token.balanceOf(alice), 15 ether);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), 15 ether);
        assertEq(token.totalMinted(), 25 ether);
    }

    function test_TransferMovesTokens() public {
        _mint(alice, 10 ether);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 4 ether));

        assertEq(token.balanceOf(alice), 6 ether);
        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.totalSupply(), 10 ether);
    }

    function test_TransferFromMovesTokens() public {
        _mint(alice, 10 ether);

        vm.prank(alice);
        token.approve(bob, 4 ether);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 4 ether));

        assertEq(token.balanceOf(alice), 6 ether);
        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), 10 ether);
    }

    function test_OwnershipTransfersOnlyAfterAcceptance() public {
        address next = makeAddr("next");

        vm.prank(owner);
        token.transferOwnership(next);

        assertEq(token.owner(), owner);
        assertEq(token.pendingOwner(), next);

        vm.prank(next);
        token.acceptOwnership();

        assertEq(token.owner(), next);
        assertEq(token.pendingOwner(), address(0));

        vm.prank(next);
        token.mint(alice, 1 ether);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.totalMinted(), 1 ether);
    }

    function test_RevertWhen_MintExceedsCap() public {
        uint256 amount = token.MAX_SUPPLY() + 1;

        _expectLifetimeCap(0, amount);
        _mint(alice, amount);

        assertEq(token.totalMinted(), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_BurnDoesNotFreeMintingRoom() public {
        _mint(alice, token.MAX_SUPPLY());

        vm.prank(alice);
        token.burn(1 ether);

        assertLt(token.totalSupply(), token.totalMinted());
        assertEq(token.totalMinted(), token.MAX_SUPPLY());

        _expectLifetimeCap(token.MAX_SUPPLY(), 1);
        _mint(bob, 1);
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.mint(alice, 1 ether);

        assertEq(token.totalMinted(), 0);
    }

    function test_RevertWhen_MintToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0)));
        _mint(address(0), 1 ether);

        assertEq(token.totalMinted(), 0);
    }

    function test_RevertWhen_MintAmountIsZero() public {
        vm.expectRevert(DriverToken.DriverToken__ZeroAmount.selector);
        _mint(alice, 0);

        assertEq(token.totalMinted(), 0);
    }

    function test_RevertWhen_BurnExceedsBalance() public {
        _mint(alice, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether));
        vm.prank(alice);
        token.burn(11 ether);

        assertEq(token.totalMinted(), 10 ether);
        assertEq(token.totalSupply(), 10 ether);
    }

    function test_RevertWhen_BurnFromExceedsAllowance() public {
        _mint(alice, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        vm.prank(bob);
        token.burnFrom(alice, 1 ether);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.totalMinted(), 10 ether);
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        _mint(alice, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether));
        vm.prank(alice);
        assertFalse(token.transfer(bob, 11 ether));

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhen_InitialOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new DriverToken(address(0));
    }

    function _mint(address to, uint256 amount) internal {
        vm.prank(owner);
        token.mint(to, amount);
    }

    function _expectLifetimeCap(uint256 totalMinted, uint256 amount) internal {
        uint256 maxSupply = token.MAX_SUPPLY();
        vm.expectRevert(
            abi.encodeWithSelector(
                DriverToken.DriverToken__LifetimeMintCapExceeded.selector, totalMinted, amount, maxSupply
            )
        );
    }
}
