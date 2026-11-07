// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IOfficialPool} from "../src/interfaces/IOfficialPool.sol";
import {ITreasuryFund} from "../src/interfaces/ITreasuryFund.sol";
import {DemoDriverClock} from "../src/DemoDriverClock.sol";
import {DeployDriver} from "./DeployDriver.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {TaxSplitter} from "../src/TaxSplitter.sol";

/// @title Simulate Driver
/// @notice Runs the demo loop in memory and writes one JSON file. Nothing is broadcast.
contract SimulateDriver is Script {
    /// @notice Fixed clock at the start of every run.
    uint256 public constant START = 1_700_000_000;

    /// @notice Account that claims, swaps, locks, and votes. It is not a deployer.
    address public constant USER = address(uint160(1));

    /// @notice Where {run} writes the eighteen runs.
    string public constant OUTPUT = "../frontend/src/content/simulation.json";

    /// @notice One recorded moment.
    struct Step {
        string id;
        uint256 walletDvr;
        uint256 walletUsdc;
        uint256 lockedDvr;
        uint256 poolDvr;
        uint256 poolUsdc;
        uint256 taxFund1;
        uint256 taxFund2;
        uint256 taxFund3;
        uint256 fund1Value;
        uint256 fund2Value;
        uint256 fund1Pending;
        uint256 fund2Pending;
        uint256 fund1BoughtBack;
        uint256 fund2BoughtBack;
        uint256 fund1BuybackSpent;
        uint256 fund1DvrBurned;
        uint256 fund2BuybackSpent;
        uint256 fund2DvrBurned;
        uint256 totalSupply;
        uint256 rebalanceAmount;
    }

    /// @notice One full run.
    struct Outcome {
        DeployDriver.Deployed deployed;
        uint256 firstRebalance;
        uint256 secondRebalance;
        Step[11] steps;
    }

    /// @notice The script was started on a chain other than local Anvil.
    /// @param chainId The active chain id.
    error SimulateDriver__LocalOnly(uint256 chainId);

    /// @notice Writes all eighteen runs to {OUTPUT}.
    /// @dev Reverts with {SimulateDriver__LocalOnly} before any deploy when the chain is not Anvil.
    function run() external {
        _requireLocal();
        vm.warp(START);
        uint256 snap = vm.snapshotState();
        uint256[3] memory swaps = [uint256(25), 50, 100];
        string[3] memory votes = ["highway", "autobahn", "drift"];
        string[] memory runs = new string[](18);
        uint256 index;
        for (uint256 swapIndex; swapIndex < swaps.length; ++swapIndex) {
            for (uint256 lockIndex; lockIndex < 2; ++lockIndex) {
                for (uint256 voteIndex; voteIndex < votes.length; ++voteIndex) {
                    vm.revertToState(snap);
                    bool lockAll = lockIndex == 1;
                    Outcome memory outcome = _play(swaps[swapIndex] * 10 ** 6, lockAll, uint8(voteIndex));
                    runs[index] =
                        _runJson(swaps[swapIndex] * 10 ** 6, lockAll ? "all" : "half", votes[voteIndex], outcome.steps);
                    ++index;
                }
            }
        }
        vm.writeFile(OUTPUT, _root(runs));
    }

    /// @notice Plays the 100 mUSDC, lock-all, Drift run and returns the ending figures.
    /// @dev Reverts with {SimulateDriver__LocalOnly} before any deploy when the chain is not Anvil.
    /// @return supply DVR supply after the second harvest.
    /// @return burned DVR burned after the second harvest.
    /// @return farm Fund 2's active farm after the second harvest.
    /// @return drift The Drift farm from that deploy.
    /// @return firstMove mUSDC the first rebalance moved.
    /// @return secondMove mUSDC the second rebalance moved.
    function previewDrift()
        external
        returns (uint256 supply, uint256 burned, address farm, address drift, uint256 firstMove, uint256 secondMove)
    {
        _requireLocal();
        vm.warp(START);
        Outcome memory outcome = _play(100 * 10 ** 6, true, 2);
        supply = outcome.deployed.token.totalSupply();
        burned = outcome.deployed.token.totalMinted() - supply;
        farm = address(outcome.deployed.degenDriver.activeFarm());
        drift = address(outcome.deployed.drift);
        firstMove = outcome.firstRebalance;
        secondMove = outcome.secondRebalance;
    }

    /// @dev Deploys a fresh demo and walks one visitor through two epochs.
    function _play(uint256 swapUsdc, bool lockAll, uint8 voteIndex) private returns (Outcome memory outcome) {
        HelperConfig helper = new HelperConfig();
        vm.deal(helper.ANVIL_DEPLOYER(), 1000 ether);
        outcome.deployed = new DeployDriver().run();
        DeployDriver.Deployed memory deployed = outcome.deployed;
        address deployer = helper.ANVIL_DEPLOYER();
        uint256 epoch = helper.EPOCH_LENGTH();

        outcome.steps[0] = _snapshot(deployed, "start");
        vm.startPrank(USER);
        deployed.dvrFaucet.claim();
        deployed.usdcFaucet.claim();
        vm.stopPrank();
        outcome.steps[1] = _snapshot(deployed, "claim");

        vm.startPrank(USER);
        deployed.usdc.approve(address(deployed.pool), swapUsdc);
        deployed.pool.swapExactInput(IOfficialPool.Direction.Buy, swapUsdc, 0, block.timestamp);
        vm.stopPrank();
        outcome.steps[2] = _snapshot(deployed, "swap");

        uint256 lockAmount = deployed.token.balanceOf(USER);
        if (!lockAll) {
            lockAmount = lockAmount / 2;
        }
        vm.startPrank(USER);
        deployed.token.approve(address(deployed.vote), lockAmount);
        deployed.vote.lock(lockAmount);
        vm.stopPrank();
        outcome.steps[3] = _snapshot(deployed, "lock");

        vm.prank(USER);
        if (voteIndex == 0) {
            deployed.vote.vote(deployed.highway);
        } else if (voteIndex == 1) {
            deployed.vote.vote(deployed.autobahn);
        } else {
            deployed.vote.vote(deployed.drift);
        }
        outcome.steps[4] = _snapshot(deployed, "vote");

        vm.prank(deployer);
        DemoDriverClock(address(deployed.clock)).advanceTime(epoch);
        outcome.steps[5] = _snapshot(deployed, "skip");

        vm.prank(deployer);
        deployed.cruiseControl.harvest(0);
        outcome.steps[6] = _snapshot(deployed, "harvest-fund-1");
        vm.prank(deployer);
        deployed.degenDriver.harvest(0);
        outcome.steps[7] = _snapshot(deployed, "harvest-fund-2");
        outcome.firstRebalance = outcome.steps[7].rebalanceAmount;

        vm.prank(deployer);
        DemoDriverClock(address(deployed.clock)).advanceTime(epoch);
        outcome.steps[8] = _snapshot(deployed, "skip-again");

        vm.prank(deployer);
        deployed.cruiseControl.harvest(0);
        outcome.steps[9] = _snapshot(deployed, "harvest-fund-1-again");
        vm.prank(deployer);
        deployed.degenDriver.harvest(0);
        outcome.steps[10] = _snapshot(deployed, "harvest-fund-2-again");
        outcome.secondRebalance = outcome.steps[10].rebalanceAmount;
    }

    /// @dev Reads the contracts. It does not compute a swap.
    function _snapshot(DeployDriver.Deployed memory deployed, string memory id)
        private
        view
        returns (Step memory step)
    {
        step.id = id;
        step.walletDvr = deployed.token.balanceOf(USER);
        step.walletUsdc = deployed.usdc.balanceOf(USER);
        step.lockedDvr = deployed.vote.locked(USER);
        step.poolDvr = deployed.pool.reserveDvr();
        step.poolUsdc = deployed.pool.reserveUsdc();
        step.taxFund1 = deployed.splitter.accrued(TaxSplitter.FundId.Fund1);
        step.taxFund2 = deployed.splitter.accrued(TaxSplitter.FundId.Fund2);
        step.taxFund3 = deployed.splitter.accrued(TaxSplitter.FundId.Fund3);
        step.fund1Value = deployed.cruiseControl.value();
        step.fund2Value = deployed.degenDriver.value();
        step.fund1Pending = deployed.cruiseControl.pendingRewards();
        step.fund2Pending = deployed.degenDriver.pendingRewards();
        step.fund1BoughtBack = deployed.cruiseControl.dvrBoughtBack();
        step.fund2BoughtBack = deployed.degenDriver.dvrBoughtBack();
        ITreasuryFund.Harvest memory fund1 = deployed.cruiseControl.lastHarvest();
        step.fund1BuybackSpent = fund1.buybackSpent;
        step.fund1DvrBurned = fund1.dvrBurned;
        ITreasuryFund.Harvest memory fund2 = deployed.degenDriver.lastHarvest();
        step.fund2BuybackSpent = fund2.buybackSpent;
        step.fund2DvrBurned = fund2.dvrBurned;
        step.totalSupply = deployed.token.totalSupply();
        (bool executed,,,, uint256 amount) = deployed.degenDriver.lastRebalance();
        if (executed) {
            step.rebalanceAmount = amount;
        }
    }

    /// @dev Anvil only. A fork or a public chain stops here.
    function _requireLocal() private view {
        if (block.chainid != 31337) {
            revert SimulateDriver__LocalOnly(block.chainid);
        }
    }

    /// @dev One run object. Amounts are decimal strings.
    function _runJson(uint256 swapUsdc, string memory lockMode, string memory vote, Step[11] memory steps)
        private
        pure
        returns (string memory json)
    {
        string memory body = string.concat(
            _num("swapUsdc", swapUsdc),
            ",",
            _str("lock", lockMode),
            ",",
            _str("vote", vote),
            ",\"steps\":[",
            _stepJson(steps[0])
        );
        for (uint256 i = 1; i < steps.length; ++i) {
            body = string.concat(body, ",", _stepJson(steps[i]));
        }
        json = string.concat("{", body, "]}");
    }

    /// @dev The file contents, with a trailing newline.
    function _root(string[] memory runs) private pure returns (string memory json) {
        string memory body =
            string.concat(_num("startTimestamp", START), ",", _num("epochSeconds", 30 days), ",\"runs\":[", runs[0]);
        for (uint256 i = 1; i < runs.length; ++i) {
            body = string.concat(body, ",", runs[i]);
        }
        json = string.concat("{", body, "]}\n");
    }

    /// @dev One step object.
    function _stepJson(Step memory step) private pure returns (string memory json) {
        json = string.concat(
            "{",
            _str("id", step.id),
            ",",
            _num("walletDvr", step.walletDvr),
            ",",
            _num("walletUsdc", step.walletUsdc),
            ",",
            _num("lockedDvr", step.lockedDvr),
            ",",
            _num("poolDvr", step.poolDvr),
            ",",
            _num("poolUsdc", step.poolUsdc),
            ",",
            _num("taxFund1", step.taxFund1),
            ",",
            _num("taxFund2", step.taxFund2),
            ",",
            _num("taxFund3", step.taxFund3),
            ",",
            _amounts(step),
            "}"
        );
    }

    /// @dev The second half of a step object, without braces.
    function _amounts(Step memory step) private pure returns (string memory json) {
        json = string.concat(
            _num("fund1Value", step.fund1Value),
            ",",
            _num("fund2Value", step.fund2Value),
            ",",
            _num("fund1Pending", step.fund1Pending),
            ",",
            _num("fund2Pending", step.fund2Pending),
            ",",
            _num("fund1BoughtBack", step.fund1BoughtBack),
            ",",
            _num("fund2BoughtBack", step.fund2BoughtBack),
            ",",
            _num("fund1BuybackSpent", step.fund1BuybackSpent),
            ",",
            _num("fund1DvrBurned", step.fund1DvrBurned),
            ",",
            _num("fund2BuybackSpent", step.fund2BuybackSpent),
            ",",
            _num("fund2DvrBurned", step.fund2DvrBurned),
            ",",
            _num("totalSupply", step.totalSupply),
            ",",
            _num("rebalanceAmount", step.rebalanceAmount)
        );
    }

    /// @dev `"key":"value"` for text.
    function _str(string memory key, string memory value) private pure returns (string memory field) {
        field = string.concat("\"", key, "\":\"", value, "\"");
    }

    /// @dev `"key":"decimal"` for an amount.
    function _num(string memory key, uint256 value) private pure returns (string memory field) {
        field = string.concat("\"", key, "\":\"", vm.toString(value), "\"");
    }
}
