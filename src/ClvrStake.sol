// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ClvrSlashing} from "./ClvrSlashing.sol";

contract ClvrStake {
    event StakedScheduler(PoolId indexed poolId, address indexed scheduler);
    event UnstakedScheduler(PoolId indexed poolId, address indexed scheduler);

    uint256 public constant STAKE_AMOUNT = 1 ether;

    mapping(PoolId => mapping(address => bool)) public stakedSchedulers; // per pool addresses that can schedule swaps

    modifier onlyStakedScheduler(PoolKey calldata key, address scheduler) {
        require(isStakedScheduler(key, scheduler), "Only staked schedulers can call this function");
        _;
    }
    
    constructor() {}

    function _stake(PoolKey calldata key, address scheduler) internal {
        stakedSchedulers[key.toId()][scheduler] = true;
        emit StakedScheduler(key.toId(), scheduler);
    }

    function _unstake(PoolKey calldata key, address scheduler) internal {
        stakedSchedulers[key.toId()][scheduler] = false;
        emit UnstakedScheduler(key.toId(), scheduler);
    }

    function isStakedScheduler(PoolKey calldata key, address scheduler) public view returns (bool) {
        return stakedSchedulers[key.toId()][scheduler];
    }
}
