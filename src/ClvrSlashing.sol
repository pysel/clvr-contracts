// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ClvrHook} from "./ClvrHook.sol";
import {ClvrModel} from "./ClvrModel.sol";

/// @title ClvrSlashing
/// @author Ruslan Akhtariev
/// @notice This contract is responsible for slashing invalid batches of swaps.
contract ClvrSlashing {
    /// @notice Emitted when a batch is disputed
    /// @param poolId The pool ID
    /// @param batchIndex The index of the batch
    /// @param creator The address of the creator of the batch
    /// @param disputer The address of the disputer
    event BatchDisputed(PoolId indexed poolId, uint256 batchIndex, address creator, address disputer);

    /// @notice How many batches are simultaneously kept in memory as a graceful period for slashing
    uint256 public constant BATCH_RETENTION_PERIOD = 5;

    /// @notice Magic value to return when a batch is disputed successfully
    bytes4 public constant BATCH_DISPUTED_MAGIC_VALUE = bytes4(keccak256("BATCH_DISPUTED"));

    /// @notice A struct to store a batch of swaps
    /// @param creator The address of the creator of the batch
    /// @param p0 The initial price
    /// @param swaps The swaps in the batch
    /// @param disputed Whether the batch has been disputed
    struct RetainedBatch {
        address creator;
        uint256 p0;
        ClvrHook.SwapParamsExtended[] swaps;
        bool disputed;
    }

    // per-pool queue of retained batches
    // 0'th element is the oldest batch, (BATCH_RETENTION_PERIOD - 1)'th is the newest
    mapping(PoolId => RetainedBatch[BATCH_RETENTION_PERIOD]) public retainedBatches;

    ClvrModel private model;

    constructor() {
        model = new ClvrModel(0, 0);
    }

    /// Adds a new batch to the queue, pushing the oldest batch out
    /// @param key The pool key
    /// @param newBatch The new batch of swaps
    function addBatch(PoolKey calldata key, ClvrHook.SwapParamsExtended[] memory newBatch, address creator, uint256 p0) public {
        RetainedBatch[BATCH_RETENTION_PERIOD] storage batch = retainedBatches[key.toId()];
        for (uint256 i = 0; i < batch.length - 1; i++) {
            batch[i].swaps = batch[i+1].swaps;
        }
        batch[batch.length - 1].swaps = newBatch;
        batch[batch.length - 1].creator = creator;
        batch[batch.length - 1].p0 = p0;
    }
    
    /// Disputes a batch, which means that the caller is claiming that there is an ordering that provides lower volatility.
    /// @param key The pool key
    /// @param batchIndex The index of the batch to dispute
    /// @param betterReordering i'th element is the index of the swap in the batch that should be i'th in the correct ordering
    /// @return magic Whether the batch was disputed successfully (i.e. the initial ordering was not correct)
    function _disputeBatch(PoolKey calldata key, uint256 batchIndex, uint256[] memory betterReordering) internal returns (bytes4) {
        require(batchIndex < BATCH_RETENTION_PERIOD, "Batch index out of bounds");
        require(!retainedBatches[key.toId()][batchIndex].disputed, "Batch already disputed");

        RetainedBatch storage batch = retainedBatches[key.toId()][batchIndex];
        uint256 batchSize = batch.swaps.length;

        require(betterReordering.length == batchSize, "Invalid reordering length");

        ClvrHook.SwapParamsExtended[] memory suggestedOrdering = new ClvrHook.SwapParamsExtended[](batch.swaps.length);
        for (uint256 i = 0; i < batchSize; i++) {
            suggestedOrdering[i] = batch.swaps[betterReordering[i]];
        }

        if (model.isBetterOrdering(batch.p0, batch.swaps, suggestedOrdering)) {
            batch.disputed = true;

            emit BatchDisputed(key.toId(), batchIndex, batch.creator, msg.sender);

            return BATCH_DISPUTED_MAGIC_VALUE;
        }

        return bytes4(0);
    }
}