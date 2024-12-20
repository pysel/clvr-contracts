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

    /// @notice The minimum number of blocks that must pass before a batch can be executed
    uint256 public constant BATCH_PERIOD = 5; 

    /// @notice Block number of the last batch
    uint256 public lastBatchBlock;

    /// @notice Uniswap v4 temporary test swap router, must change before deploying
    PoolSwapTest swapRouter;

    /// @notice Modifier to check if the batch period has passed since the last batch
    modifier batchIsReady() {
        require(block.number >= lastBatchBlock + BATCH_PERIOD, "Batch is not ready");
        _;
    }

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
        address,
        PoolKey calldata key,
        uint256,
        uint256,
        bytes calldata data // array of swapIds encoded as bytes32[]
    ) external override onlyStakedScheduler(key, tx.origin) batchIsReady returns (bytes4) { // origin because the hook is called by a proxy contract
        PoolId poolId = key.toId();

        uint256[] memory swapIds = abi.decode(data, (uint256[]));
        require(nextSwapKey[poolId] == swapIds.length, "Swap Ids length does not match the size of the scheduled swaps");

        SwapParamsExtended[] memory batchedSwaps = new SwapParamsExtended[](swapIds.length);
        for (uint256 i = 0; i < swapIds.length; i++) {
            batchedSwaps[i] = swapParams[poolId][swapIds[i]];
        }

        for (uint256 i = 0; i < swapIds.length; ) {
            SwapParamsExtended memory paramsE = batchedSwaps[i];

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

        (uint256 reserve_x, uint256 reserve_y) = getCurrentReserves(key);

        // retain the batch
        RetainedBatch memory batch = RetainedBatch({
            creator: tx.origin,
            p0: getCurrentPrice(key),
            reserveX: reserve_x,
            reserveY: reserve_y,
            swaps: batchedSwaps,
            disputed: false
        });

        // add the batch to the retained set
        addBatch(key, batch);

        emit BatchCompleted(poolId);

        lastBatchBlock = block.number;
        
        return BaseHook.beforeDonate.selector;
    }

    // STAKING

    /// @notice Stakes the scheduler for the pool
    /// @param key The pool key
    /// @param scheduler The scheduler address
    function stake(PoolKey calldata key, address scheduler) payable public {
        require(msg.value == STAKE_AMOUNT, "Must stake at least 1 ETH");
        _stake(key, scheduler);
    }

    /// @notice Unstakes the scheduler from the pool
    /// @notice Can only be called if the scheduler has no recent batches (so there is time to dispute their latest batches)
    /// @dev The scheduler address is the sender of the transaction
    /// @param key The pool key
    function unstake(PoolKey calldata key) public onlyStakedScheduler(key, msg.sender) {
        for (uint256 i = 0; i < ClvrSlashing.BATCH_RETENTION_PERIOD; i++) {
            if (retainedBatches[key.toId()][i].creator == msg.sender) {
                revert("Scheduler has a recent batch, wait for it to be displaced by newer batches");
            }
        }

        _unstake(key, msg.sender);

        payable(msg.sender).transfer(STAKE_AMOUNT);
    }

    /// @notice Disputes a batch of swaps
    /// @param key The pool key
    /// @param batchIndex The index of the batch to dispute
    /// @param betterReordering The reordering of swaps that is better than the retained batch
    function disputeBatch(PoolKey calldata key, uint256 batchIndex, uint256[] memory betterReordering) public {
        require(batchIndex < ClvrSlashing.BATCH_RETENTION_PERIOD, "Batch index out of bounds");
        require(!retainedBatches[key.toId()][batchIndex].disputed, "Batch already disputed");
        
        bytes4 magic = _disputeBatch(key, batchIndex, betterReordering);
        if (magic == ClvrSlashing.BATCH_DISPUTED_MAGIC_VALUE) {
            payable(msg.sender).transfer(ClvrStake.STAKE_AMOUNT);
        }

        address slashedCreator = retainedBatches[key.toId()][batchIndex].creator;
        _unstake(key, slashedCreator); // unstakes without paying back the stake to the batch creator
    }

    // QUERIES

    /// @notice Returns all scheduled swaps for a given pool
    /// @param key The pool key
    /// @return swaps The scheduled swaps
    function getScheduledSwaps(PoolKey calldata key) view public returns (SwapParamsExtended[] memory) {
        SwapParamsExtended[] memory swaps = new SwapParamsExtended[](nextSwapKey[key.toId()]);
        for (uint256 i = 0; i < nextSwapKey[key.toId()]; i++) {
            swaps[i] = swapParams[key.toId()][i];
        }
        return swaps;
    }

    /// @notice Returns the current price of the pool
    /// @param key The pool key
    /// @return price The current price
    function getCurrentPrice(PoolKey calldata key) view public returns (uint256) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        uint256 decimals = 10 **
            ERC20(Currency.unwrap(key.currency1)).decimals();
        uint256 sqrtPrice = (sqrtPriceX96 * decimals) / 2 ** 96; // get sqrtPrice with decimals of token
        return sqrtPrice ** 2 / decimals;
    }

    /// @notice Returns the current reserves of the pool (the ones on which clvr computations should happen)
    /// Not real reserves, but are implied from the current price, only needed for clvr computations
    /// @param key The pool key
    /// @return reserve0 The current reserve of the first currency
    /// @return reserve1 The current reserve of the second currency
    function getCurrentReserves(PoolKey calldata key) view public returns (uint256, uint256) { // TODO: think about this when decimals of two tokens are different
        uint256 currentPrice = getCurrentPrice(key);
        uint256 reserve0 = currentPrice;
        uint256 reserve1 = 1e18;

        return (reserve0, reserve1);
    }
}
