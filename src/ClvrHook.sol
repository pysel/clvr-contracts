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
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {ClvrStake} from "./ClvrStake.sol";
import {ClvrSlashing} from "./ClvrSlashing.sol";

import {console} from "forge-std/console.sol";


/// @title ClvrHook
/// @author Ruslan Akhtariev
/// @notice This is a Uniswap v4 hook that implements the Clvr protocol.
/// * It allows to schedule swaps and execute batches of swaps according to the Clvr model.
/// * Anyone can schedule a swap, but only staked schedulers can schedule a batch.
/// * Incorrectly scheduled batch can be disputed by anyone and a batch creator slashed accordingly.
contract ClvrHook is BaseHook, ClvrStake, ClvrSlashing {
    using SafeCast for *;
    using StateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;

    /// @notice Emitted when a batch of swaps is completed
    /// @param poolId The pool id
    event BatchCompleted(PoolId poolId);

    /// @notice Emitted when a swap is scheduled
    /// @param poolId The pool id
    /// @param sender The address that scheduled the swap
    event SwapScheduled(PoolId poolId, address sender);

    /// @notice Extended swap parameters
    /// @custom:field sender The address that scheduled the swap
    /// @custom:field recepient The address that will receive the swap
    /// @custom:field params The swap parameters
    struct SwapParamsExtended {
        address sender;
        address recepient;
        IPoolManager.SwapParams params;
    }

    /// @notice The address a scheduler provides to indicate a hook that this is a time to perform a batch.
    address private constant BATCH = address(0);

    /// @notice List of scheduled swaps per pool
    mapping(PoolId => mapping(uint256 => SwapParamsExtended)) public swapParams;

    /// @notice The key for the next swap to be scheduled per pool.
    mapping(PoolId => uint256) public nextSwapKey;

    PoolSwapTest swapRouter;

    constructor(IPoolManager _manager, PoolSwapTest _swapRouter) BaseHook(_manager) {
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

        // Store the swap params
        swapParams[poolId][nextSwapKey[poolId]] = paramsE;
        nextSwapKey[poolId]++;

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
        bytes calldata data // array of swapIds encoded as bytes32[]
    ) external override onlyStakedScheduler(key, sender) returns (bytes4) {
        PoolId poolId = key.toId();

        uint256[] memory swapIds = abi.decode(data, (uint256[]));
        require(nextSwapKey[poolId] == swapIds.length, "All scheduled swaps must be executed");

        for (uint256 i = 0; i < swapIds.length; ) {
            SwapParamsExtended memory paramsE = swapParams[poolId][swapIds[i]];

            // Execute the swap
            poolManager.swap(key, paramsE.params, abi.encode(BATCH));

            int256 delta0 = poolManager.currencyDelta(address(this), key.currency0);
            int256 delta1 = poolManager.currencyDelta(address(this), key.currency1);

            if (delta0 < 0) {
                key.currency0.settle(poolManager, address(this), uint256(-delta0), true);
            }
            
            if (delta1 < 0) {
                key.currency1.settle(poolManager, address(this), uint256(-delta1), true);
            }

            if (delta0 > 0) {
                key.currency0.take(poolManager, paramsE.recepient, uint256(delta0), false);
            }

            if (delta1 > 0) {
                key.currency1.take(poolManager, paramsE.recepient, uint256(delta1), false);
            }

            delete swapParams[poolId][swapIds[i]];

            unchecked {
                i++;
            }
        }

        nextSwapKey[poolId] = 0;
        
        return BaseHook.beforeDonate.selector;
    }

    // STAKING

    /// @notice Stakes the scheduler for the pool
    /// @param key The pool key
    /// @param scheduler The scheduler address
    function stake(PoolKey calldata key, address scheduler) payable public {
        require(msg.value == STAKE_AMOUNT, "Must stake 1 ETH to stake");
        _stake(key, scheduler);
    }

    /// @notice Unstakes the scheduler from the pool
    /// @notice Can only be called if the scheduler has no recent batches (so there is time to dispute their latest batches)
    /// @param key The pool key
    /// @param scheduler The scheduler address
    function unstake(PoolKey calldata key, address scheduler) external onlyStakedScheduler(key, scheduler) {
        for (uint256 i = 0; i < ClvrSlashing.BATCH_RETENTION_PERIOD; i++) {
            if (retainedBatches[key.toId()][i].creator == scheduler) {
                revert("Scheduler has a recent batch, wait for it to be displaced by newer batches");
            }
        }

        _unstake(key, scheduler);

        payable(msg.sender).transfer(STAKE_AMOUNT);
    }

    function disputeBatch(PoolKey calldata key, uint256 batchIndex, uint256[] memory betterReordering) public {
        bytes4 magic = _disputeBatch(key, batchIndex, betterReordering);
        if (magic == ClvrSlashing.BATCH_DISPUTED_MAGIC_VALUE) {
            payable(msg.sender).transfer(ClvrStake.STAKE_AMOUNT);
        }

        address slashedCreator = retainedBatches[key.toId()][batchIndex].creator;
        _unstake(key, slashedCreator); // unstakes without paying back the stake to the batch creator
    }

    function getCurrentPrice(PoolKey calldata key) view internal returns (uint256) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        uint256 decimals = 10 **
            ERC20(Currency.unwrap(key.currency1)).decimals();
        uint256 sqrtPrice = (sqrtPriceX96 * decimals) / 2 ** 96; // get sqrtPrice with decimals of token
        return sqrtPrice ** 2 / decimals;
    }

    // QUERIES

    /// @notice Returns all scheduled swaps for a given pool
    /// @param key The pool key
    /// @return swaps The scheduled swaps
    function getScheduledSwaps(PoolKey calldata key) view external returns (SwapParamsExtended[] memory) {
        SwapParamsExtended[] memory swaps = new SwapParamsExtended[](nextSwapKey[key.toId()]);
        for (uint256 i = 0; i < nextSwapKey[key.toId()]; i++) {
            swaps[i] = swapParams[key.toId()][i];
        }
        return swaps;
    }
}
