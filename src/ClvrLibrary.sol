// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClvrIntentPool } from "./ClvrIntentPool.sol";

library ClvrLibrary {
    struct CLVRIntent {
        address creator;
        address tokenIn;
        address tokenOut;
        address recipient;
        uint24 fee;
        uint256 amountIn;
        uint256 deadline;
    }

    address internal constant EMPTY_ADDRESS = address(0);
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant INVALID_SIGNATURE = ~MAGICVALUE;

    function getPoolKey(address tokenIn, address tokenOut, uint24 fee) external pure returns (bytes32) {
        return keccak256(abi.encode(tokenIn, tokenOut, fee));
    }

}
