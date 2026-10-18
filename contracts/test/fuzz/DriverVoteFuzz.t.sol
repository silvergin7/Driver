// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMockFarm} from "../../src/interfaces/IMockFarm.sol";
import {CruiseControl} from "../../src/CruiseControl.sol";
import {DegenDriver} from "../../src/DegenDriver.sol";
import {DemoDriverClock} from "../../src/DemoDriverClock.sol";
import {DriverToken} from "../../src/DriverToken.sol";
import {DriverVote} from "../../src/DriverVote.sol";
import {MockFarm} from "../../src/MockFarm.sol";
import {MockUSDC} from "../../src/MockUSDC.sol";
import {OfficialPool} from "../../src/OfficialPool.sol";
import {RoundSchedule} from "../../src/RoundSchedule.sol";
import {TaxSplitter} from "../../src/TaxSplitter.sol";

contract DriverVoteFuzzTest is Test, IERC20Errors {
    uint256 internal constant SHARE_1 = 15_000 * 10 ** 6;
    uint256 internal constant SHARE_2 = 5_000 * 10 ** 6;

    DriverToken internal token;
    RoundSchedule internal schedule;
    MockFarm internal highway;
    MockFarm internal autobahn;
    MockFarm internal drift;
    DriverVote internal vote;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        MockUSDC usdc = new MockUSDC(owner);
        token = new DriverToken(owner);
        DemoDriverClock clock = new DemoDriverClock(owner);
        TaxSplitter splitter = new TaxSplitter(usdc, owner);
        OfficialPool pool = new OfficialPool(token, usdc, splitter, owner, 100);
        schedule = new RoundSchedule(clock, 30 days);
        vm.prank(owner);
        splitter.setPool(address(pool));

        MockFarm cruiseFarm = new MockFarm(usdc, clock, 500, owner);
        highway = new MockFarm(usdc, clock, 4_000, owner);
        autobahn = new MockFarm(usdc, clock, 8_000, owner);
        drift = new MockFarm(usdc, clock, 16_000, owner);
        IMockFarm[] memory cruiseFarms = new IMockFarm[](1);
        cruiseFarms[0] = cruiseFarm;
        CruiseControl cruise =
            new CruiseControl(usdc, clock, schedule, splitter, pool, SHARE_1, SHARE_2, cruiseFarms, owner);
        IMockFarm[] memory farms = new IMockFarm[](3);
        farms[0] = highway;
        farms[1] = autobahn;
        farms[2] = drift;
        DegenDriver degen =
            new DegenDriver(usdc, clock, schedule, splitter, pool, cruise, SHARE_1, SHARE_2, farms, owner);
        vote = new DriverVote(token, schedule, degen);

        vm.prank(owner);
        token.mint(alice, 1_000 ether);
    }

    function testFuzz_SecondLockAddsItsWeight(uint256 first, uint256 second, uint256 farmSeed) public {
        uint256 balance = token.balanceOf(alice);
        first = bound(first, 1, balance - 1);
        second = bound(second, 1, balance - first);
        IMockFarm farm = _farm(farmSeed);

        _lock(alice, first);
        vm.prank(alice);
        vote.vote(farm);
        _lock(alice, second);

        assertEq(vote.tally(0, address(farm)), first + second);
        assertEq(vote.locked(alice), first + second);
        assertEq(vote.counted(), first + second);
        assertEq(token.balanceOf(address(vote)), first + second);
    }

    function testFuzz_UnlockSliceWhenNotVoted(uint256 locked, uint256 slice) public {
        uint256 balance = token.balanceOf(alice);
        locked = bound(locked, 1, balance);
        slice = bound(slice, 1, locked);
        _lock(alice, locked);

        vm.prank(alice);
        vote.unlock(slice);

        assertEq(vote.locked(alice), locked - slice);
        assertEq(vote.counted(), locked - slice);
        assertEq(token.balanceOf(address(vote)), locked - slice);
        assertEq(token.balanceOf(alice), balance - locked + slice);
        assertEq(vote.tally(0, address(highway)), 0);
    }

    function testFuzz_RevertWhen_UnlockAfterAVote(uint256 locked, uint256 slice) public {
        uint256 balance = token.balanceOf(alice);
        locked = bound(locked, 1, balance);
        slice = bound(slice, 1, locked);
        _lock(alice, locked);
        vm.prank(alice);
        vote.vote(highway);

        uint256 unlocksAt = schedule.roundEnd(0);
        vm.expectRevert(abi.encodeWithSelector(DriverVote.DriverVote__Voted.selector, 0, unlocksAt));
        vm.prank(alice);
        vote.unlock(slice);

        assertEq(vote.locked(alice), locked);
        assertEq(vote.tally(0, address(highway)), locked);
    }

    function testFuzz_RevertWhen_AmountIsZero(uint256 choice) public {
        choice = bound(choice, 0, 1);
        if (choice == 0) {
            vm.expectRevert(DriverVote.DriverVote__ZeroAmount.selector);
            vm.prank(alice);
            vote.lock(0);
            assertEq(vote.counted(), 0);
            return;
        }

        _lock(alice, 1);
        vm.expectRevert(DriverVote.DriverVote__ZeroAmount.selector);
        vm.prank(alice);
        vote.unlock(0);
        assertEq(vote.locked(alice), 1);
    }

    function testFuzz_RevertWhen_LockExceedsBalance(uint256 amount) public {
        uint256 balance = token.balanceOf(alice);
        amount = bound(amount, balance + 1, balance + 1_000 ether);

        vm.startPrank(alice);
        token.approve(address(vote), amount);
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, alice, balance, amount));
        vote.lock(amount);
        vm.stopPrank();

        assertEq(vote.counted(), 0);
        assertEq(token.balanceOf(address(vote)), 0);
    }

    function _farm(uint256 farmSeed) private view returns (IMockFarm farm) {
        uint256 index = bound(farmSeed, 0, 2);
        if (index == 0) {
            return highway;
        }
        if (index == 1) {
            return autobahn;
        }
        return drift;
    }

    function _lock(address holder, uint256 amount) private {
        vm.startPrank(holder);
        token.approve(address(vote), amount);
        vote.lock(amount);
        vm.stopPrank();
    }
}
