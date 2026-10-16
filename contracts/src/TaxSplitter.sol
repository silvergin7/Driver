// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MockUSDC} from "./MockUSDC.sol";

/// @title Taxed pool pointer
/// @notice Getter the official pool exposes so {TaxSplitter.setPool} can confirm where its tax goes.
/// @dev {OfficialPool} satisfies this with its `i_taxSplitter` immutable. The splitter does not import
/// that contract: the pool imports the splitter, and a second import would cycle.
interface ITaxedPool {
    /// @notice Returns the splitter this pool pays.
    /// @return i_taxSplitter_ Splitter that receives the pool's USDC tax.
    function i_taxSplitter() external view returns (address i_taxSplitter_);
}

/// @title Tax splitter
/// @notice Holds the official pool's USDC tax in three fund buckets.
/// @dev The pool transfers USDC here, then calls {accrue}. {accrue} records the split and does not call
/// another contract. Fund 1 and Fund 2 each receive the floored 40 percent. Fund 3 receives the rest,
/// including at most two wei of division dust, so the buckets sum to the accrued amount. A recipient is
/// set once. {release} pays `msg.sender` only when that caller is the bucket's recipient. Tokens sent
/// here directly are not credited and cannot be released. Renouncing ownership freezes {setPool} and
/// {setRecipient}, so a bucket that was never assigned stays in this contract.
contract TaxSplitter is ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice One fund bucket.
    enum FundId {
        Fund1,
        Fund2,
        Fund3
    }

    /// @notice Denominator for the fund shares. 10_000 is 100 percent.
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Fund 1's share of each accrual, in basis points.
    uint256 public constant FUND_1_BPS = 4_000;

    /// @notice Fund 2's share of each accrual, in basis points.
    uint256 public constant FUND_2_BPS = 4_000;

    /// @notice Fund 3's nominal share of each accrual, in basis points.
    /// @dev The stored Fund 3 amount is the remainder, so it is this share plus any division dust.
    uint256 public constant FUND_3_BPS = 2_000;

    /// @notice Mock USDC this splitter accounts for.
    MockUSDC public immutable i_usdc;

    address private s_pool;
    mapping(FundId fundId => address recipient) private s_recipient;
    mapping(FundId fundId => uint256 amount) private s_accrued;

    /// @notice Emitted when the owner sets the pool.
    /// @param pool Pool allowed to call {accrue}.
    event PoolSet(address indexed pool);

    /// @notice Emitted when the owner sets a fund recipient.
    /// @param fundId Bucket whose recipient changed.
    /// @param recipient Account that may release that bucket.
    event RecipientSet(FundId indexed fundId, address indexed recipient);

    /// @notice Emitted when the pool records a tax payment.
    /// @param amount USDC the pool transferred before the call, in base units.
    /// @param fund1Share Amount added to Fund 1, in base units.
    /// @param fund2Share Amount added to Fund 2, in base units.
    /// @param fund3Share Amount added to Fund 3, in base units.
    event TaxAccrued(uint256 amount, uint256 fund1Share, uint256 fund2Share, uint256 fund3Share);

    /// @notice Emitted when a recipient releases its bucket.
    /// @param fundId Bucket that was paid.
    /// @param recipient Account that received the USDC.
    /// @param amount Amount transferred, in base units.
    event TaxReleased(FundId indexed fundId, address indexed recipient, uint256 amount);

    /// @notice An address argument was zero.
    error TaxSplitter__ZeroAddress();

    /// @notice The amount was zero.
    error TaxSplitter__ZeroAmount();

    /// @notice The pool was already set.
    error TaxSplitter__PoolAlreadySet();

    /// @notice The pool does not report this splitter as its tax destination.
    /// @param pool Account passed to {setPool}.
    error TaxSplitter__PoolMismatch(address pool);

    /// @notice The caller is not the pool.
    /// @param caller Account that called {accrue}.
    error TaxSplitter__CallerNotPool(address caller);

    /// @notice That fund already has a recipient.
    /// @param fundId Bucket that was already assigned.
    error TaxSplitter__RecipientAlreadySet(FundId fundId);

    /// @notice That fund has no recipient.
    /// @param fundId Bucket with no recipient.
    error TaxSplitter__RecipientNotSet(FundId fundId);

    /// @notice The caller is not that fund's recipient.
    /// @param fundId Bucket the caller tried to release.
    /// @param caller Account that called {release}.
    error TaxSplitter__CallerNotRecipient(FundId fundId, address caller);

    /// @notice Sets the token and the owner. No pool and no recipients are set.
    /// @param usdc Mock USDC the pool will transfer. The zero address is rejected.
    /// @param initialOwner Account allowed to set the pool and the recipients. The zero address is rejected.
    constructor(MockUSDC usdc, address initialOwner) Ownable(initialOwner) {
        if (address(usdc) == address(0)) {
            revert TaxSplitter__ZeroAddress();
        }
        i_usdc = usdc;
    }

    /// @notice Sets the only account allowed to call {accrue}.
    /// @dev Reverts with {TaxSplitter__PoolAlreadySet} on a second call. Reverts with
    /// {TaxSplitter__PoolMismatch} unless `newPool.i_taxSplitter()` equals this contract. That view runs
    /// before the address is stored. `nonReentrant` blocks a reentrant {setPool}.
    /// @param newPool Official pool that pays this splitter. The zero address is rejected.
    function setPool(address newPool) external nonReentrant onlyOwner {
        if (newPool == address(0)) {
            revert TaxSplitter__ZeroAddress();
        }
        if (s_pool != address(0)) {
            revert TaxSplitter__PoolAlreadySet();
        }
        if (ITaxedPool(newPool).i_taxSplitter() != address(this)) {
            revert TaxSplitter__PoolMismatch(newPool);
        }
        s_pool = newPool;
        emit PoolSet(newPool);
    }

    /// @notice Sets the account allowed to release one fund.
    /// @dev Reverts with {TaxSplitter__RecipientAlreadySet} when that bucket already has a recipient.
    /// The recipient cannot be changed later.
    /// @param fundId Bucket to assign.
    /// @param newRecipient Account that may call {release} for `fundId`. The zero address is rejected.
    function setRecipient(FundId fundId, address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) {
            revert TaxSplitter__ZeroAddress();
        }
        if (s_recipient[fundId] != address(0)) {
            revert TaxSplitter__RecipientAlreadySet(fundId);
        }
        s_recipient[fundId] = newRecipient;
        emit RecipientSet(fundId, newRecipient);
    }

    /// @notice Records a tax payment the pool has already transferred.
    /// @dev Reverts with {TaxSplitter__CallerNotPool} unless the caller is the stored pool, and with
    /// {TaxSplitter__ZeroAmount} when `amount` is zero. Fund 1 and Fund 2 are
    /// `floor(amount * share / {BPS_DENOMINATOR})`. Fund 3 is the remainder. This function does not
    /// transfer tokens and does not call another contract.
    /// @param amount USDC just transferred to this contract, in base units. Must be greater than zero.
    function accrue(uint256 amount) external nonReentrant {
        if (msg.sender != s_pool) {
            revert TaxSplitter__CallerNotPool(msg.sender);
        }
        if (amount == 0) {
            revert TaxSplitter__ZeroAmount();
        }

        uint256 fund1Share = Math.mulDiv(amount, FUND_1_BPS, BPS_DENOMINATOR);
        uint256 fund2Share = Math.mulDiv(amount, FUND_2_BPS, BPS_DENOMINATOR);
        uint256 fund3Share = amount - fund1Share - fund2Share;
        s_accrued[FundId.Fund1] += fund1Share;
        s_accrued[FundId.Fund2] += fund2Share;
        s_accrued[FundId.Fund3] += fund3Share;
        emit TaxAccrued(amount, fund1Share, fund2Share, fund3Share);
    }

    /// @notice Pays one fund's accrued USDC to its recipient.
    /// @dev Reverts with {TaxSplitter__RecipientNotSet} when that bucket has no recipient, then with
    /// {TaxSplitter__CallerNotRecipient} when the caller is someone else, then with
    /// {TaxSplitter__ZeroAmount} when the bucket is empty. The bucket is cleared before the transfer.
    /// USDC is sent to `msg.sender`.
    /// @param fundId Bucket to pay.
    function release(FundId fundId) external nonReentrant {
        address recipient_ = s_recipient[fundId];
        if (recipient_ == address(0)) {
            revert TaxSplitter__RecipientNotSet(fundId);
        }
        if (msg.sender != recipient_) {
            revert TaxSplitter__CallerNotRecipient(fundId, msg.sender);
        }
        uint256 amount = s_accrued[fundId];
        if (amount == 0) {
            revert TaxSplitter__ZeroAmount();
        }

        s_accrued[fundId] = 0;
        IERC20(i_usdc).safeTransfer(msg.sender, amount);
        emit TaxReleased(fundId, msg.sender, amount);
    }

    /// @notice Returns the account allowed to call {accrue}.
    /// @return pool_ The pool. The zero address means {setPool} has not been called.
    function pool() public view returns (address pool_) {
        pool_ = s_pool;
    }

    /// @notice Returns the account allowed to release `fundId`.
    /// @param fundId Bucket to query.
    /// @return recipient_ The recipient. The zero address means that bucket has not been assigned.
    function recipient(FundId fundId) public view returns (address recipient_) {
        recipient_ = s_recipient[fundId];
    }

    /// @notice Returns the USDC still owed to `fundId`.
    /// @param fundId Bucket to query.
    /// @return accrued_ Unpaid amount, in base units.
    function accrued(FundId fundId) public view returns (uint256 accrued_) {
        accrued_ = s_accrued[fundId];
    }
}
