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

    PoolId poolId;
    ClvrHook hook;

    address[5] users;

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

    function initUsers() internal {
        users[0] = makeAddr("Alice");
        users[1] = makeAddr("Bob");
        users[2] = makeAddr("Carol");
        users[3] = makeAddr("3");
        users[4] = makeAddr("4");
    }

    function dealCurrencyToUsers() internal {
        for (uint256 i = 0; i < users.length; i++) {
            deal(Currency.unwrap(currency0), users[i], 100e18);
            deal(Currency.unwrap(currency1), users[i], 100e18);
        }
    }

    function approveSwapRouter() internal {
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            ERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
            ERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
            vm.stopPrank();
        }
    }

    function approveHook() internal {
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            ERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
            ERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
            vm.stopPrank();
        }
    }

    // function approveHookForUsers() public {

    function testHookSanity() public {
        dealCurrencyToUsers();
        approveSwapRouter();
        approveHook();

        address sender = users[0];
        bytes memory hookData = abi.encode(sender);

        int256 amount = -1e18;
        bool zeroForOne = true;
        // console.log(currency0.balanceOf(address(this)));
        // console.log(currency1.balanceOf(address(this)));
        // console.log();

        // console.log(currency0.balanceOf(sender));
        // console.log(currency1.balanceOf(sender));

        uint256 c0balance = currency0.balanceOf(sender);
        uint256 c1balance = currency1.balanceOf(sender);

        vm.startPrank(sender, sender);
        swap(key, zeroForOne, amount, hookData);
        vm.stopPrank();

        require(currency0.balanceOf(sender) + uint256(-amount) == c0balance, "Currency0 balance should be decreased by amount");
        require(currency1.balanceOf(sender) == c1balance, "Currency1 balance should not be changed");

        // console.log(currency0.balanceOf(address(this)));
        // console.log(currency1.balanceOf(address(this)));
        // console.log();

        // console.log(currency1.balanceOf(sender));
        // console.log(currency0.balanceOf(sender));
        // console.log(currency1.balanceOf(address(hook)));

        // console.log(currency1.balanceOf(sender));
        donateRouter.donate(key, 0, 0, "");

        require(currency1.balanceOf(sender) > c1balance, "Swap should have increased currency1 balance");

        // console.log(currency1.balanceOf(sender));
        // console.log(currency0.balanceOf(sender));
        // console.log(currency1.balanceOf(address(hook)));
    }
}