// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";


import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ClvrIntentPool } from "./ClvrIntentPool.sol";
import { ClvrModel } from "./ClvrModel.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {ClvrStake} from "./ClvrStake.sol";

import {console} from "forge-std/console.sol";


contract ClvrHook is BaseHook, ClvrStake {
    using SafeCast for *;
    using StateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;

    event BatchCompleted(PoolId poolId);

    event SwapScheduled(PoolId poolId, address sender);

    struct SwapParamsExtended {
        address sender;
        address recepient;
        IPoolManager.SwapParams params;
    }

    address private constant BATCH = address(0);

    mapping(PoolId => mapping(bytes32 => SwapParamsExtended)) public swapParams; // per pool scheduled swaps (their params)

    ClvrModel private model;
    PoolSwapTest swapRouter;

    constructor(IPoolManager _manager, PoolSwapTest _swapRouter) BaseHook(_manager) {
        model = new ClvrModel(0, 0);
        swapRouter = _swapRouter;
    }

    function getHookPermissions()
        public
        pure
        virtual
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        require(
            params.amountSpecified < 0,
            "Clvr Pools only work with exact input swaps"
        );

        address recepient = abi.decode(data, (address));

        if (recepient == BATCH) {
            if (!isStakedScheduler(key, sender)) {
                revert("Only staked schedulers can schedule batched swaps");
            }

            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        PoolId poolId = PoolIdLibrary.toId(key);

        // the hook takes the exact amount of the input currency to itself
        Currency input = params.zeroForOne ? key.currency0 : key.currency1;
        uint256 amountTaken = uint256(-params.amountSpecified);
        poolManager.mint(address(this), input.toId(), amountTaken);

        SwapParamsExtended memory paramsE = SwapParamsExtended({
            sender: sender,
            recepient: recepient,
            params: params
        });

        bytes32 swapId = keccak256(abi.encode(sender, params));

        // Store the swap params
        swapParams[poolId][swapId] = paramsE;

        emit SwapScheduled(poolId, sender);

        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(amountTaken.toInt128(), 0),
            0
        );
    }

    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256,
        uint256,
        bytes calldata data
    ) external override onlyStakedScheduler(key, sender) returns (bytes4) {
        PoolId poolId = key.toId();

        return BaseHook.beforeDonate.selector;
    }

    function getCurrentPrice(PoolKey calldata key) view internal returns (uint256) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        uint256 decimals = 10 **
            ERC20(Currency.unwrap(key.currency1)).decimals();
        uint256 sqrtPrice = (sqrtPriceX96 * decimals) / 2 ** 96; // get sqrtPrice with decimals of token
        return sqrtPrice ** 2 / decimals;
    }

    function _unlockCallback(
        bytes calldata data
    ) internal override returns (bytes memory) {}
}