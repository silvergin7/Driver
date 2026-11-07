// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {SimulateDriver} from "../../script/SimulateDriver.s.sol";

contract SimulateDriverTest is Test {
    function test_DriftRunBurnsAndRebalances() public {
        (uint256 supply, uint256 burned, address farm, address drift, uint256 firstMove, uint256 secondMove) =
            new SimulateDriver().previewDrift();

        assertEq(farm, drift);
        assertEq(firstMove, 0);
        assertGt(secondMove, 0);
        assertGt(burned, 0);
        assertEq(supply + burned, 1_000_000 ether);
    }

    function test_RevertWhen_PreviewOnMainnet() public {
        SimulateDriver simulator = new SimulateDriver();
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SimulateDriver.SimulateDriver__LocalOnly.selector, 1));
        simulator.previewDrift();
    }
}
