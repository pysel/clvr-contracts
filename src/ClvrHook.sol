// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ClvrIntentPool } from "./ClvrIntentPool.sol";
import { ClvrModel } from "./ClvrModel.sol";


contract ClvrHook is BaseHook {
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    struct SwapParamsExtended {
        address recepient;
        IPoolManager.SwapParams params;
    }

    address private constant BATCH = address(0);

    mapping(PoolId => SwapParamsExtended[]) public swapParams;

    ClvrModel private model;

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions()
        public
        pure
        virtual
        override
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
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
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata data)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        require(params.amountSpecified < 0, "Clvr Pools only work with exact input swaps");

        PoolId poolId = PoolIdLibrary.toId(key);
        address recepient = abi.decode(data, (address));

        if (recepient == BATCH) { // TODO: make sure this can't easily be called
            // perform the swap right away
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        Currency input = params.zeroForOne ? key.currency0 : key.currency1;
        uint256 amountTaken = uint256(params.amountSpecified);
        poolManager.mint(address(this), input.toId(), amountTaken);

        SwapParamsExtended memory paramsE = SwapParamsExtended({
            recepient: recepient,
            params: params
        });

        // Store the swap params
        swapParams[poolId].push(paramsE);

        return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(amountTaken.toInt128(), 0), 0);
    }

    function beforeDonate(address, PoolKey calldata key, uint256, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();

        SwapParamsExtended[] memory params = swapParams[poolId];
        if (params.length == 0) {
            return BaseHook.beforeDonate.selector;
        }

        (uint160 sqrtPriceX96, , ,) = poolManager.getSlot0(poolId);
        uint256 decimals = 10 ** ERC20(Currency.unwrap(key.currency1)).decimals();
        uint256 sqrtPrice = (sqrtPriceX96 * decimals) / 2 ** 96; // get sqrtPrice with decimals of token
        uint256 currentPrice = sqrtPrice ** 2 / decimals;

        params = model.clvrReorder(currentPrice, params, currentPrice * 1e18, 1e18/currentPrice); // currentPrice hack to simulate token amounts

        for (uint256 i = 0; i < params.length; i++) {
            poolManager.swap(
                key,
                params[i].params,
                abi.encode(BATCH)
            );
        }

        return BaseHook.beforeDonate.selector;
    }

    // function sqrtPriceX96ToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
    //     uint256 priceX96 = uint256(sqrtPriceX96).mul(uint256(sqrtPriceX96)).mul(1e18) >> (96 * 2);
    //     return priceX96;
    // }

}