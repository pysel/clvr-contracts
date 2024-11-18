// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ClvrIntentPool } from "./ClvrIntentPool.sol";
import { ClvrLibrary } from "./ClvrLibrary.sol";

contract ClvrExecutor {
    ClvrIntentPool private intentPool;
    ISwapRouter private swapRouter;

    constructor(address intentPool_, address swapRouter_) {
        intentPool = ClvrIntentPool(intentPool_);
        swapRouter = ISwapRouter(swapRouter_);
    }

    /**
     * @notice Execute a batch of intents
     * @param statusQuoPrice The starting price         TODO: get this in contract
     * @param poolKey The identifier for the pool through which the intents are being executed
     * @param intents The intents to execute
     */
    function executeBatch(uint256 statusQuoPrice, bytes32 poolKey, ClvrLibrary.CLVRIntent[] memory intents) public {
        // uint256[] memory volumes = new uint256[](intents.length);
        for (uint256 i = 0; i < intents.length; i++) {
            bytes32 intentHash = keccak256(abi.encode(intents[i]));

            bytes4 verification = intentPool.intentExists(poolKey, intentHash);

            if (verification != ClvrLibrary.MAGICVALUE) {
                revert("Invalid Intent Passed to Executor");
            }
        }
    }

    function executeIntent(ClvrLibrary.CLVRIntent memory intent) private {
        IERC20(intent.tokenIn).transferFrom(intent.creator, address(this), intent.amountIn);
        IERC20(intent.tokenIn).approve(address(swapRouter), intent.amountIn);

        uint256 amountOut = swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: intent.tokenIn,
            tokenOut: intent.tokenOut,
            fee: intent.fee,
            recipient: intent.recipient,
            deadline: block.timestamp,
            amountIn: intent.amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));

        IERC20(intent.tokenOut).transfer(intent.recipient, amountOut);

        // emit IntentExecuted(intent.creator, intent.tokenIn, intent.tokenOut, intent.recipient, intent.fee, intent.amountIn, amountOut);
    }
}
