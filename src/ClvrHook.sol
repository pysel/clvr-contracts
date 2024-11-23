// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

import { ClvrIntentPool } from "./ClvrIntentPool.sol";
import { ClvrModel } from "./ClvrModel.sol";


contract ClvrHook is BaseHook {
    using SafeCast for *;

    struct SwapParamsExtended {
        address recepient;
        IPoolManager.SwapParams params;
    }

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

        Currency input = params.zeroForOne ? key.currency0 : key.currency1;
        uint256 amountTaken = uint256(params.amountSpecified);
        poolManager.mint(address(this), input.toId(), amountTaken);

        address recepient = abi.decode(data, (address));

        SwapParamsExtended memory paramsE = SwapParamsExtended({
            recepient: recepient,
            params: params
        });

        // Store the swap params
        swapParams[poolId].push(paramsE);

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
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

        // ClvrModel.TradeMinimal[] memory trades = swapParamsToTradeMinimalArrays(params);


    }

    // function swapParamsToTradeMinimalArrays(SwapParamsExtended[] memory params) internal view returns (ClvrModel.TradeMinimal[] memory) {
    //     ClvrModel.TradeMinimal[] memory tradeMinimals = new ClvrModel.TradeMinimal[](params.length);

    //     // append null trade at the beginning
    //     tradeMinimals[0] = ClvrModel.TradeMinimal({
    //         direction: ClvrModel.Direction.NULL,
    //         amountIn: 0
    //     });

    //     for (uint256 i = 0; i < params.length; i++) {
    //         tradeMinimals[i + 1] = swapParamsToTradeMinimal(params[i]);
    //     }
    //     return tradeMinimals;
    // }

    // function swapParamsToTradeMinimal(SwapParamsExtended memory params) internal view returns (ClvrModel.TradeMinimal memory) {
    //     return ClvrModel.TradeMinimal({
    //         direction: params.params.zeroForOne ? ClvrModel.Direction.Buy : ClvrModel.Direction.Sell,
    //         amountIn: uint256(-params.params.amountSpecified)
    //     });
    // }
}