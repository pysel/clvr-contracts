# Smart Contracts for CLVR ordering

This repository contains the smart contracts for the CLVR ordering mechanism. It is built on top of Uniswap V4 as a hook.

## Logic

The ordering is enforced by an "optimistic" infrastructure model. Anyone can schedule a swap, but only staked schedulers can execute them.
If a staked scheduler is found to have submitted an invalid ordering, their stake is slashed.

### Execution Flow

1. A user executes a normal swap against the Uniswap V4 pool.
2. `beforeSwap` hook is called. It mints ERC6909 claims of a Uniswap poolmanager for a hook and does not perform an actual swap (NoOp).
3. When a scheduler is ready to execute a batch, they can initiate a donation to the pool. `beforeDonate` hook is called, to which the scheduler submits a CLVR reordering of the swaps submitted by users so far. Then, it executes all the pending swaps according to the submitted ordering.
4. `beforeDonate` saves the batch temporarily in the contract's state.
5. Until `BATCH_RETENTION_PERIOD` other batches are executed, any user can dispute the batch submitted in step 3. If the batch is disputed, a better ordering is submitted by a user. A contract calculates the volatility of a proposed ordering and saved ordering. If the volatility of a proposed ordering is lower than the volatility of a saved ordering, the batch is considered faulty, and the scheduler's stake is slashed. Otherwise, a disputing user gets nothing.

### Notes

- A scheduler cannot unstake while retention batches contain a batch that was executed by them. This prevents a scheduler from submitting an invalid batch and unstaking immediately after.
- Pool reserves are computed from the current price by estimating the proportion, not the actual amounts. Hence, the queries cannot be used to get concrete amounts of the pool reserves, rather only relative values.

## Contracts

- `ClvrHook.sol`: The entrypoint contract for the CLVR ordering protocol.
- `ClvrModel.sol`: The model that describes the rule by which swaps are ordered.
- `ClvrLn.sol`: A small library for calculating the natural logarithm of a number times 1e18.
- `ClvrSlashing.sol`: A contract that handles the slashing of schedulers that do not follow the protocol correctly.
- `ClvrStake.sol`: A contract that handles the staking of schedulers.

## Tests

Unit tests can be ran by executing `forge test`.
