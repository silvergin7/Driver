// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";

contract PoolPointer {
    address public immutable i_taxSplitter;

    constructor(address splitter) {
        i_taxSplitter = splitter;
    }
}

contract TaxSplitterTest is Test {
    MockUSDC internal token;
    TaxSplitter internal splitter;
    PoolPointer internal pointer;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal fund1 = makeAddr("fund1");
    address internal fund2 = makeAddr("fund2");
    address internal fund3 = makeAddr("fund3");

    event PoolSet(address indexed pool);
    event RecipientSet(TaxSplitter.FundId indexed fundId, address indexed recipient);
    event TaxAccrued(uint256 amount, uint256 fund1Share, uint256 fund2Share, uint256 fund3Share);
    event TaxReleased(TaxSplitter.FundId indexed fundId, address indexed recipient, uint256 amount);

    function setUp() public {
        token = new MockUSDC(owner);
        splitter = new TaxSplitter(token, owner);
        pointer = new PoolPointer(address(splitter));
    }

    function test_ConstructorSetsTokenAndOwner() public view {
        assertEq(address(splitter.i_usdc()), address(token));
        assertEq(splitter.owner(), owner);
        assertEq(splitter.pool(), address(0));
        assertEq(splitter.BPS_DENOMINATOR(), 10_000);
        assertEq(splitter.FUND_1_BPS() + splitter.FUND_2_BPS() + splitter.FUND_3_BPS(), splitter.BPS_DENOMINATOR());
    }

    function test_RevertWhen_UsdcIsZeroAddress() public {
        vm.expectRevert(TaxSplitter.TaxSplitter__ZeroAddress.selector);
        new TaxSplitter(MockUSDC(address(0)), owner);
    }

    function test_RevertWhen_OwnerIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new TaxSplitter(token, address(0));
    }

    function test_SetPoolStoresThePool() public {
        _setPool();

        assertEq(splitter.pool(), address(pointer));
    }

    function test_SetPoolEmitsPoolSet() public {
        vm.expectEmit(address(splitter));
        emit PoolSet(address(pointer));

        _setPool();
    }

    function test_RevertWhen_PoolIsZeroAddress() public {
        vm.expectRevert(TaxSplitter.TaxSplitter__ZeroAddress.selector);
        vm.prank(owner);
        splitter.setPool(address(0));

        assertEq(splitter.pool(), address(0));
    }

    function test_RevertWhen_PoolIsSetTwice() public {
        _setPool();

        vm.expectRevert(TaxSplitter.TaxSplitter__PoolAlreadySet.selector);
        vm.prank(owner);
        splitter.setPool(address(pointer));

        assertEq(splitter.pool(), address(pointer));
    }

    function test_RevertWhen_PoolPointsAtAnotherSplitter() public {
        PoolPointer wrong = new PoolPointer(makeAddr("other"));

        vm.expectRevert(abi.encodeWithSelector(TaxSplitter.TaxSplitter__PoolMismatch.selector, address(wrong)));
        vm.prank(owner);
        splitter.setPool(address(wrong));

        assertEq(splitter.pool(), address(0));
    }

    function test_RevertWhen_SetPoolCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        splitter.setPool(address(pointer));

        assertEq(splitter.pool(), address(0));
    }

    function test_SetRecipientStoresTheRecipient() public {
        _setRecipient(TaxSplitter.FundId.Fund1, fund1);

        assertEq(splitter.recipient(TaxSplitter.FundId.Fund1), fund1);
        assertEq(splitter.recipient(TaxSplitter.FundId.Fund2), address(0));
    }

    function test_SetRecipientEmitsRecipientSet() public {
        vm.expectEmit(address(splitter));
        emit RecipientSet(TaxSplitter.FundId.Fund1, fund1);

        _setRecipient(TaxSplitter.FundId.Fund1, fund1);
    }

    function test_RevertWhen_RecipientIsZeroAddress() public {
        vm.expectRevert(TaxSplitter.TaxSplitter__ZeroAddress.selector);
        vm.prank(owner);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, address(0));

        assertEq(splitter.recipient(TaxSplitter.FundId.Fund1), address(0));
    }

    function test_RevertWhen_RecipientIsSetTwice() public {
        _setRecipient(TaxSplitter.FundId.Fund1, fund1);

        vm.expectRevert(
            abi.encodeWithSelector(TaxSplitter.TaxSplitter__RecipientAlreadySet.selector, TaxSplitter.FundId.Fund1)
        );
        vm.prank(owner);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, fund2);

        assertEq(splitter.recipient(TaxSplitter.FundId.Fund1), fund1);
    }

    function test_RevertWhen_SetRecipientCallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, fund1);

        assertEq(splitter.recipient(TaxSplitter.FundId.Fund1), address(0));
    }

    function test_AccrueSplitsOneMillionEvenly() public {
        _setPool();
        _accrue(1_000_000);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 200_000);
    }

    function test_AccruePutsDustInFund3() public {
        _setPool();
        _accrue(203);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 81);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 81);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 41);

        _accrue(1);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 81);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 81);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 42);
    }

    function test_AccrueDoesNotMoveTokens() public {
        _setPool();
        vm.prank(owner);
        token.mint(address(splitter), 1_000_000);
        uint256 balanceBefore = token.balanceOf(address(splitter));

        vm.prank(address(pointer));
        splitter.accrue(1_000_000);

        assertEq(token.balanceOf(address(splitter)), balanceBefore);
        assertEq(token.balanceOf(address(pointer)), 0);
    }

    function test_AccrueEmitsTaxAccrued() public {
        _setPool();
        vm.prank(owner);
        token.mint(address(splitter), 203);

        vm.expectEmit(address(splitter));
        emit TaxAccrued(203, 81, 81, 41);

        vm.prank(address(pointer));
        splitter.accrue(203);
    }

    function test_RevertWhen_AccrueAmountIsZero() public {
        _setPool();

        vm.expectRevert(TaxSplitter.TaxSplitter__ZeroAmount.selector);
        vm.prank(address(pointer));
        splitter.accrue(0);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 0);
    }

    function test_RevertWhen_AccrueCallerIsNotPool() public {
        _setPool();

        vm.expectRevert(abi.encodeWithSelector(TaxSplitter.TaxSplitter__CallerNotPool.selector, alice));
        vm.prank(alice);
        splitter.accrue(1);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 0);
    }

    function test_RevertWhen_AccrueBeforePoolIsSet() public {
        vm.expectRevert(abi.encodeWithSelector(TaxSplitter.TaxSplitter__CallerNotPool.selector, address(pointer)));
        vm.prank(address(pointer));
        splitter.accrue(1);
    }

    function test_ReleaseSendsTheBucketToTheRecipient() public {
        _setPool();
        _setRecipient(TaxSplitter.FundId.Fund1, fund1);
        _setRecipient(TaxSplitter.FundId.Fund2, fund2);
        _setRecipient(TaxSplitter.FundId.Fund3, fund3);
        _accrue(1_000_000);

        vm.prank(fund1);
        splitter.release(TaxSplitter.FundId.Fund1);

        assertEq(token.balanceOf(fund1), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 400_000);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 200_000);
        assertEq(token.balanceOf(address(splitter)), 600_000);
    }

    function test_ReleaseEmitsTaxReleased() public {
        _setPool();
        _setRecipient(TaxSplitter.FundId.Fund1, fund1);
        _accrue(1_000_000);

        vm.expectEmit(address(splitter));
        emit TaxReleased(TaxSplitter.FundId.Fund1, fund1, 400_000);

        vm.prank(fund1);
        splitter.release(TaxSplitter.FundId.Fund1);
    }

    function test_RevertWhen_ReleaseBeforeRecipientIsSet() public {
        _setPool();
        _accrue(1_000_000);

        vm.expectRevert(
            abi.encodeWithSelector(TaxSplitter.TaxSplitter__RecipientNotSet.selector, TaxSplitter.FundId.Fund1)
        );
        vm.prank(fund1);
        splitter.release(TaxSplitter.FundId.Fund1);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(token.balanceOf(fund1), 0);
    }

    function test_RevertWhen_ReleaseCallerIsNotRecipient() public {
        _setPool();
        _setRecipient(TaxSplitter.FundId.Fund1, fund1);
        _accrue(1_000_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                TaxSplitter.TaxSplitter__CallerNotRecipient.selector, TaxSplitter.FundId.Fund1, alice
            )
        );
        vm.prank(alice);
        splitter.release(TaxSplitter.FundId.Fund1);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(fund1), 0);
    }

    function test_RevertWhen_ReleaseAmountIsZero() public {
        _setRecipient(TaxSplitter.FundId.Fund1, fund1);

        vm.expectRevert(TaxSplitter.TaxSplitter__ZeroAmount.selector);
        vm.prank(fund1);
        splitter.release(TaxSplitter.FundId.Fund1);
    }

    function test_DirectTransferStaysAfterEveryRelease() public {
        _setPool();
        _setRecipient(TaxSplitter.FundId.Fund1, fund1);
        _setRecipient(TaxSplitter.FundId.Fund2, fund2);
        _setRecipient(TaxSplitter.FundId.Fund3, fund3);
        _accrue(1_000_000);
        vm.prank(owner);
        token.mint(address(splitter), 7);

        vm.prank(fund1);
        splitter.release(TaxSplitter.FundId.Fund1);
        vm.prank(fund2);
        splitter.release(TaxSplitter.FundId.Fund2);
        vm.prank(fund3);
        splitter.release(TaxSplitter.FundId.Fund3);

        assertEq(token.balanceOf(address(splitter)), 7);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund2), 0);
        assertEq(splitter.accrued(TaxSplitter.FundId.Fund3), 0);
    }

    function test_RenounceLeavesUnsetRecipientStuck() public {
        _setPool();
        _accrue(1_000_000);

        vm.prank(owner);
        splitter.renounceOwnership();

        assertEq(splitter.owner(), address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        splitter.setRecipient(TaxSplitter.FundId.Fund1, fund1);

        vm.expectRevert(
            abi.encodeWithSelector(TaxSplitter.TaxSplitter__RecipientNotSet.selector, TaxSplitter.FundId.Fund1)
        );
        vm.prank(fund1);
        splitter.release(TaxSplitter.FundId.Fund1);

        assertEq(splitter.accrued(TaxSplitter.FundId.Fund1), 400_000);
        assertEq(token.balanceOf(address(splitter)), 1_000_000);
    }

    function _setPool() internal {
        vm.prank(owner);
        splitter.setPool(address(pointer));
    }

    function _setRecipient(TaxSplitter.FundId fundId, address recipient_) internal {
        vm.prank(owner);
        splitter.setRecipient(fundId, recipient_);
    }

    function _accrue(uint256 amount) internal {
        vm.prank(owner);
        token.mint(address(splitter), amount);
        vm.prank(address(pointer));
        splitter.accrue(amount);
    }
}
