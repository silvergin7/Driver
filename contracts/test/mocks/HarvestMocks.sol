// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDriverClock} from "../../src/interfaces/IDriverClock.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {IOfficialPool} from "../../src/interfaces/IOfficialPool.sol";
import {IStrategyBallot} from "../../src/interfaces/IStrategyBallot.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {TreasuryFund} from "../../src/TreasuryFund.sol";

/// @title Fixed farm
/// @notice Test farm that returns a fixed claim and can call harvest from claim.
contract FixedFarm is IMockFarm {
    MockUSDC private immutable i_usdc_;
    IDriverClock private immutable i_clock_;
    TreasuryFund private s_fund;
    uint256 private s_claim;
    bool private s_reenter;

    /// @notice Stores the token and the clock the fund constructor reads.
    /// @param usdc Mock USDC reported by this farm.
    /// @param clock Clock reported by this farm.
    constructor(MockUSDC usdc, IDriverClock clock) {
        i_usdc_ = usdc;
        i_clock_ = clock;
    }

    /// @notice Sets the claim amount and whether {claim} calls harvest.
    /// @param fund Fund {claim} calls when `reenter` is true.
    /// @param claimAmount Amount {claim} returns, in base units.
    /// @param reenter True when {claim} calls {TreasuryFund.harvest} before returning.
    function configure(TreasuryFund fund, uint256 claimAmount, bool reenter) external {
        s_fund = fund;
        s_claim = claimAmount;
        s_reenter = reenter;
    }

    /// @notice Returns the configured amount, after an optional harvest call.
    /// @return paid Configured amount, in base units.
    function claim() external returns (uint256 paid) {
        if (s_reenter) {
            s_fund.harvest(0);
        }
        paid = s_claim;
    }

    /// @notice Accepts a deposit without moving tokens.
    function deposit(uint256) external {}

    /// @notice Accepts a withdrawal without moving tokens.
    function withdraw(uint256) external {}

    /// @notice Returns zero.
    /// @return principal Zero.
    function emergencyWithdraw() external pure returns (uint256 principal) {
        principal = 0;
    }

    /// @notice Returns zero.
    /// @return accrued_ Zero.
    function accrued(address) external pure returns (uint256 accrued_) {
        accrued_ = 0;
    }

    /// @notice Returns zero.
    /// @return principal_ Zero.
    function principalOf(address) external pure returns (uint256 principal_) {
        principal_ = 0;
    }

    /// @notice Returns zero.
    /// @return totalPrincipal_ Zero.
    function totalPrincipal() external pure returns (uint256 totalPrincipal_) {
        totalPrincipal_ = 0;
    }

    /// @notice Returns zero.
    /// @return rewardReserve_ Zero.
    function rewardReserve() external pure returns (uint256 rewardReserve_) {
        rewardReserve_ = 0;
    }

    /// @notice Returns one basis point.
    /// @return aprBps_ One.
    function aprBps() external pure returns (uint256 aprBps_) {
        aprBps_ = 1;
    }

    /// @notice Returns false.
    /// @return isDepositor_ False.
    function isDepositor(address) external pure returns (bool isDepositor_) {
        isDepositor_ = false;
    }

    /// @notice Returns the token stored in the constructor.
    /// @return usdc_ Mock USDC.
    function i_usdc() external view returns (MockUSDC usdc_) {
        usdc_ = i_usdc_;
    }

    /// @notice Returns the clock stored in the constructor.
    /// @return clock_ Clock.
    function i_clock() external view returns (IDriverClock clock_) {
        clock_ = i_clock_;
    }
}

/// @title Reentering pool
/// @notice Test pool whose swap calls harvest.
contract ReenteringPool is IOfficialPool {
    MockUSDC private immutable i_usdc_;
    DriverToken private immutable i_dvr_;
    address private immutable i_splitter;
    TreasuryFund private s_fund;

    /// @notice The quote was rejected.
    error ReenteringPool__Rejected();

    /// @notice Stores the pair and the splitter the fund constructor reads.
    /// @param dvr DVR token reported by this pool.
    /// @param usdc Mock USDC reported by this pool.
    /// @param splitter Splitter reported by {i_taxSplitter}.
    constructor(DriverToken dvr, MockUSDC usdc, address splitter) {
        i_dvr_ = dvr;
        i_usdc_ = usdc;
        i_splitter = splitter;
    }

    /// @notice Stores the fund {swapExactInput} calls.
    /// @param fund Fund to call.
    function setFund(TreasuryFund fund) external {
        s_fund = fund;
    }

    /// @notice Calls harvest and returns one.
    /// @return amountOut One.
    function swapExactInput(Direction, uint256, uint256, uint256) external returns (uint256 amountOut) {
        s_fund.harvest(0);
        amountOut = 1;
    }

    /// @notice Returns one.
    /// @return amountIn One.
    function swapExactOutput(Direction, uint256, uint256, uint256) external pure returns (uint256 amountIn) {
        amountIn = 1;
    }

    /// @notice Returns one DVR and zero tax.
    /// @return amountOut One.
    /// @return usdcTax Zero.
    function quoteExactInput(Direction, uint256) external pure returns (uint256 amountOut, uint256 usdcTax) {
        amountOut = 1;
        usdcTax = 0;
    }

    /// @notice Returns the DVR token.
    /// @return dvr_ DVR token.
    function i_dvr() external view returns (DriverToken dvr_) {
        dvr_ = i_dvr_;
    }

    /// @notice Returns the Mock USDC token.
    /// @return usdc_ Mock USDC.
    function i_usdc() external view returns (MockUSDC usdc_) {
        usdc_ = i_usdc_;
    }

    /// @notice Returns the splitter stored in the constructor.
    /// @return splitter_ Splitter.
    function i_taxSplitter() external view returns (address splitter_) {
        splitter_ = i_splitter;
    }

    /// @notice Returns zero.
    /// @return reserveDvr_ Zero.
    function reserveDvr() external pure returns (uint256 reserveDvr_) {
        reserveDvr_ = 0;
    }

    /// @notice Returns zero.
    /// @return reserveUsdc_ Zero.
    function reserveUsdc() external pure returns (uint256 reserveUsdc_) {
        reserveUsdc_ = 0;
    }

    /// @notice Returns zero.
    /// @return taxBps_ Zero.
    function taxBps() external pure returns (uint256 taxBps_) {
        taxBps_ = 0;
    }
}

/// @title Rejecting pool
/// @notice Test pool whose buy quote reverts with its own error.
contract RejectingPool is IOfficialPool {
    MockUSDC private immutable i_usdc_;
    DriverToken private immutable i_dvr_;
    address private immutable i_splitter;

    /// @notice The quote was rejected.
    error RejectingPool__Rejected();

    /// @notice Stores the pair and the splitter the fund constructor reads.
    /// @param dvr DVR token reported by this pool.
    /// @param usdc Mock USDC reported by this pool.
    /// @param splitter Splitter reported by {i_taxSplitter}.
    constructor(DriverToken dvr, MockUSDC usdc, address splitter) {
        i_dvr_ = dvr;
        i_usdc_ = usdc;
        i_splitter = splitter;
    }

    /// @notice Returns zero.
    /// @return amountOut Zero.
    function swapExactInput(Direction, uint256, uint256, uint256) external pure returns (uint256 amountOut) {
        amountOut = 0;
    }

    /// @notice Returns zero.
    /// @return amountIn Zero.
    function swapExactOutput(Direction, uint256, uint256, uint256) external pure returns (uint256 amountIn) {
        amountIn = 0;
    }

    /// @notice Reverts.
    function quoteExactInput(Direction, uint256) external pure returns (uint256, uint256) {
        revert RejectingPool__Rejected();
    }

    /// @notice Returns the DVR token.
    /// @return dvr_ DVR token.
    function i_dvr() external view returns (DriverToken dvr_) {
        dvr_ = i_dvr_;
    }

    /// @notice Returns the Mock USDC token.
    /// @return usdc_ Mock USDC.
    function i_usdc() external view returns (MockUSDC usdc_) {
        usdc_ = i_usdc_;
    }

    /// @notice Returns the splitter stored in the constructor.
    /// @return splitter_ Splitter.
    function i_taxSplitter() external view returns (address splitter_) {
        splitter_ = i_splitter;
    }

    /// @notice Returns zero.
    /// @return reserveDvr_ Zero.
    function reserveDvr() external pure returns (uint256 reserveDvr_) {
        reserveDvr_ = 0;
    }

    /// @notice Returns zero.
    /// @return reserveUsdc_ Zero.
    function reserveUsdc() external pure returns (uint256 reserveUsdc_) {
        reserveUsdc_ = 0;
    }

    /// @notice Returns zero.
    /// @return taxBps_ Zero.
    function taxBps() external pure returns (uint256 taxBps_) {
        taxBps_ = 0;
    }
}

/// @title Mapped ballot
/// @notice Test ballot that returns a farm stored for each round.
contract MappedBallot is IStrategyBallot {
    mapping(uint256 roundId => IMockFarm farm) private s_winner;

    /// @notice Stores the farm `roundId` returns.
    /// @param roundId Round to set.
    /// @param farm Farm {winner} returns. The zero address is stored as itself.
    function setWinner(uint256 roundId, IMockFarm farm) external {
        s_winner[roundId] = farm;
    }

    /// @notice Returns the farm stored for `roundId`.
    /// @param roundId Round to query.
    /// @return winner_ Stored farm. The zero address is the default.
    function winner(uint256 roundId) external view returns (IMockFarm winner_) {
        winner_ = s_winner[roundId];
    }
}

/// @title Reverting ballot
/// @notice Test ballot whose winner call reverts.
contract RevertingBallot is IStrategyBallot {
    /// @notice The winner call was rejected.
    error RevertingBallot__Rejected();

    /// @notice Reverts.
    function winner(uint256) external pure returns (IMockFarm) {
        revert RevertingBallot__Rejected();
    }
}

/// @title Idle ballot
/// @notice Test ballot that returns one farm while a fund's idle matches a mark, and another after.
contract IdleBallot is IStrategyBallot {
    TreasuryFund private immutable i_fund;
    uint256 private immutable i_mark;
    IMockFarm private immutable i_first;
    IMockFarm private immutable i_second;

    /// @notice Stores the idle mark and the two farms.
    /// @param fund Fund whose idle balance is read.
    /// @param mark Idle balance that selects `first`.
    /// @param first Farm returned while idle equals `mark`.
    /// @param second Farm returned otherwise.
    constructor(TreasuryFund fund, uint256 mark, IMockFarm first, IMockFarm second) {
        i_fund = fund;
        i_mark = mark;
        i_first = first;
        i_second = second;
    }

    /// @notice Returns `first` while the fund's idle equals the mark.
    /// @return winner_ `first` or `second`.
    function winner(uint256) external view returns (IMockFarm winner_) {
        if (i_fund.idle() == i_mark) {
            winner_ = i_first;
        } else {
            winner_ = i_second;
        }
    }
}
