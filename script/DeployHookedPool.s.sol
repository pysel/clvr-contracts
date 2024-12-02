// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Constants} from "./Constants.sol";
import {console} from "forge-std/console.sol";

contract DeployHookedPool is Script, Constants {
    PoolKey pool;

    function setUp() external {
        pool = PoolKey({
            currency0: Currency.wrap(CURRENCY0),
            currency1: Currency.wrap(CURRENCY1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK_CONTRACT)
        });
    }
    function run() external {
        vm.broadcast();
        IPoolManager(POOL_MANAGER_SEPOLIA).initialize(pool, STARTING_PRICE_SQRT_X96);
    }
}
