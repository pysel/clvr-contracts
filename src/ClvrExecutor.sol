// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClvrIntentPool } from "./ClvrIntentPool.sol";
import { ClvrLibrary } from "./ClvrLibrary.sol";

contract ClvrExecutor {
    ClvrIntentPool private intentPool;

    constructor(address intentPool_, address swapRouter_) {
        intentPool = ClvrIntentPool(intentPool_);
        swapRouter = ISwapRouter(swapRouter_);
    }

    function executeBatch(ClvrIntentPool.CLVRIntent[] memory intents) public {
        bytes32 intentsHash = keccak256(abi.encode(intents));

        bytes32 verification = intentPool.isValidSignature(intentsHash, "");
        if (verification != ClvrLibrary.MAGICVALUE) {
            revert("Invalid signature");
        }


    }

    function executeIntent(ClvrIntentPool.CLVRIntent memory intent) private {

    }
}
