# Smart Contracts for CLVR ordering

This repository contains the smart contracts for the CLVR ordering mechanism. It is built on top of Uniswap V4 as a hook.

## Contracts

- `ClvrHook.sol`: The entrypoint contract for the CLVR ordering protocol.
- `ClvrModel.sol`: The model that describes the rule by which swaps are ordered.
- `ClvrLn.sol`: A small library for calculating the natural logarithm of a number times 1e18.
- `ClvrSlashing.sol`: A contract that handles the slashing of schedulers that do not follow the protocol correctly.
- `ClvrStake.sol`: A contract that handles the staking of schedulers.

## Tests

Unit tests can be ran by executing `forge test`.
