// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ClvrSlashing} from "./ClvrSlashing.sol";

contract ClvrStake {
    uint256 public constant STAKE_AMOUNT = 1 ether;

    mapping(PoolId => mapping(address => bool)) public stakedSchedulers; // per pool addresses that can schedule swaps

    modifier onlyStakedScheduler(PoolKey calldata key, address scheduler) {
        require(isStakedScheduler(key, scheduler), "Only staked schedulers can call this function");
        _;
    }
    
    constructor() {}

    function _stake(PoolKey calldata key, address scheduler) internal {
        require(msg.value == STAKE_AMOUNT, "Must stake 1 ETH to stake");
        stakedSchedulers[key.toId()][scheduler] = true;
    }

    function _unstake(PoolKey calldata key, address scheduler) internal {
        stakedSchedulers[key.toId()][scheduler] = false;
        payable(msg.sender).transfer(STAKE_AMOUNT);
    }

    function isStakedScheduler(PoolKey calldata key, address scheduler) internal view returns (bool) {
        return stakedSchedulers[key.toId()][scheduler];
    }
}
