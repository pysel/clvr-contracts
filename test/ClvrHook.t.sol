// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {ClvrHook} from "../src/ClvrHook.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";


import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolDonateTest} from "@uniswap/v4-core/src/test/PoolDonateTest.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ClvrHookTest is Test, Deployers, Fixtures {
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    bool DEBUG = true;

    PoolId poolId;
    ClvrHook hook;

    address scheduler = makeAddr("Scheduler");

    uint256 constant USERS_LENGTH = 20;

    address[USERS_LENGTH] users;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );

        bytes memory constructorArgs = abi.encode(manager, swapRouter);
        deployCodeTo("ClvrHook.sol:ClvrHook", constructorArgs, flags);
        hook = ClvrHook(flags);

        deal(address(this), 200 ether);

        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        deal(address(this), 200 ether);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                uint128(100e18)
            );

        (tokenId, ) = posm.mint(
            key,
            tickLower,
            tickUpper,
            100e18,
            amount0 + 1,
            amount1 + 1,
            address(this),
            block.timestamp,
            ""
        );

        initUsers();
    }

    function testHookSanity() public {
        dealCurrencyToUsers();
        approveSwapRouter();
        approveHook();
        stakeScheduler();

        address sender = users[0];
        bytes memory hookData = abi.encode(sender);

        int256 amount = -1e18;
        bool zeroForOne = true;

        uint256 c0balance = currency0.balanceOf(sender);
        uint256 c1balance = currency1.balanceOf(sender);

        vm.startPrank(sender, sender);
        swap(key, zeroForOne, amount, hookData);
        vm.stopPrank();

        require(currency0.balanceOf(sender) + uint256(-amount) == c0balance, "Currency0 balance should be decreased by amount");
        require(currency1.balanceOf(sender) == c1balance, "Currency1 balance should not be changed");

        uint256[] memory swapIds = new uint256[](1);
        swapIds[0] = 0;
        executeBatch(abi.encode(swapIds));

        require(currency1.balanceOf(sender) > c1balance, "Swap should have increased currency1 balance");
    }

    function testHookMultipleSwaps() public {
        dealCurrencyToUsers();
        approveSwapRouter();
        approveHook();
        stakeScheduler();

        oneBatch();
    }

    function testHookMultipleBatches() public {
        dealCurrencyToUsers();
        approveSwapRouter();
        approveHook();
        stakeScheduler();

        uint256 batches = 10;

        for (uint256 i = 0; i < batches; i++) {
            oneBatch();
        }
    }

    function testHookNonStakedSchedulerCannotExecuteBatches() public {
        dealCurrencyToUsers();
        approveSwapRouter();
        approveHook();

        uint256[] memory swapIds = getSwapIds();
        vm.startPrank(scheduler, scheduler);

        vm.expectRevert();
        executeBatch(abi.encode(swapIds));

        vm.stopPrank();
    }

    function testStakingUnstaking() public {
        uint256 initialEthBalance = 2 ether;
        deal(address(scheduler), initialEthBalance);

        vm.startPrank(scheduler, scheduler);
        hook.stake{value: initialEthBalance - 1 ether}(key, scheduler);
        vm.stopPrank();

        require(hook.isStakedScheduler(key, scheduler), "Scheduler should be staked");

        uint256 schedulerBalance = address(scheduler).balance;
        require(schedulerBalance == initialEthBalance - 1 ether, "Stake should decrease scheduler's balance by 1 ether");

        vm.startPrank(scheduler, scheduler);
        hook.unstake(key);
        vm.stopPrank();

        require(!hook.isStakedScheduler(key, scheduler), "Scheduler should not be staked");

        schedulerBalance = address(scheduler).balance;
        require(schedulerBalance == initialEthBalance, "Unstake should increase scheduler's balance by 1 ether");
    }

    function testSchedulerCannotUnstakeIfHasRecentBatches() public {
        dealCurrencyToUsers();
        approveSwapRouter();
        approveHook();
        stakeScheduler();

        sendSwaps();
        executeBatch(abi.encode(getSwapIds()));

        vm.startPrank(scheduler, scheduler);

        vm.expectRevert();
        hook.unstake(key);

        vm.stopPrank();
    }

    // UTILITY FUNCTIONS

    function stakeScheduler() internal {
        deal(address(scheduler), 1 ether);
        vm.startPrank(scheduler, scheduler);
        hook.stake{value: 1 ether}(key, scheduler);
        vm.stopPrank();

        require(hook.isStakedScheduler(key, scheduler), "Scheduler should be staked");
    }

    function initUsers() internal {
        users[0] = makeAddr("Alice");
        users[1] = makeAddr("Bob");
        users[2] = makeAddr("Carol");
        for (uint256 i = 3; i < USERS_LENGTH; i++) {
            users[i] = makeAddr(string(abi.encodePacked(i))); // users[i] = makeAddr("i") 
        }
    }

    function dealCurrencyToUsers() internal {
        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            deal(Currency.unwrap(currency0), users[i], 100e18);
            deal(Currency.unwrap(currency1), users[i], 100e18);
        }
    }

    function approveSwapRouter() internal {
        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            vm.startPrank(users[i]);
            ERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
            ERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
            vm.stopPrank();
        }
    }

    function approveHook() internal {
        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            vm.startPrank(users[i]);
            ERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
            ERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
            vm.stopPrank();
        }
    }

    function oneBatch() internal {
        uint256[] memory c0balances = new uint256[](USERS_LENGTH);
        uint256[] memory c1balances = new uint256[](USERS_LENGTH);

        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            c0balances[i] = currency0.balanceOf(users[i]);
            c1balances[i] = currency1.balanceOf(users[i]);
        }

        sendSwaps();

        // check that tokenIn balance has been taken from the user
        // check that tokenOut balance is the same as the initial balance
        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            bool zeroForOne = i % 2 == 0 ? true : false;
            if (zeroForOne) {
                require(currency0.balanceOf(users[i]) + 1e18 == c0balances[i], "Currency0 balance should be decreased by 1e18");
                require(currency1.balanceOf(users[i]) == c1balances[i], "Currency1 balance should not be changed");
            } else {
                require(currency0.balanceOf(users[i]) == c0balances[i], "Currency0 balance should not be changed");
                require(currency1.balanceOf(users[i]) + 1e18 == c1balances[i], "Currency1 balance should be decreased by 1e18");
            }
        }

        uint256 gas = gasleft();
        executeBatch(abi.encode(getSwapIds()));

        if (DEBUG) {
            console.log("Gas used in a batch execution: ", gas - gasleft(), ", approximately $", gasToDollars(gas - gasleft()));
        }

        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            bool zeroForOne = i % 2 == 0 ? true : false;
            if (zeroForOne) { // true -> getting token1 in exchange for token0, hence, token1 should increase
                require(currency1.balanceOf(users[i]) > c1balances[i], "Currency1 balance should be increased");
            } else {
                require(currency0.balanceOf(users[i]) > c0balances[i], "Currency0 balance should be increased");
            }
        }
    }

    function sendSwaps() internal {
        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            vm.startPrank(users[i], users[i]);

            uint256 gas = gasleft();
            // 0 -> buy quote, 1 -> sell quote, 2 -> buy quote, 3 -> sell quote, 4 -> buy quote
            swap(key, i % 2 == 0 ? true : false, -1e18, abi.encode(users[i]));

            if (DEBUG) {
                console.log("Gas used in swap: ", gas - gasleft(), ", approximately $", gasToDollars(gas - gasleft()));
            }

            vm.stopPrank();
        }
    }

    function executeBatch(bytes memory swapIds) internal {
        vm.startPrank(scheduler, scheduler);
        donateRouter.donate(key, 0, 0, swapIds);
        vm.stopPrank();
    }

    function getSwapIds() internal pure returns (uint256[] memory) {
        uint256[] memory swapIds = new uint256[](USERS_LENGTH);
        for (uint256 i = 0; i < USERS_LENGTH; i++) {
            swapIds[i] = i;
        }
        return swapIds;
    }

    // Estimates gas cost in dollars assuming 10 gwei per gas, 3000 USD per ETH
    function gasToDollars(uint256 gas) internal pure returns (uint256) {
        return gas * 1e9 * 30000 / 1e18;
    }
}
