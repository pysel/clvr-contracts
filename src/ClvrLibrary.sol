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

    function ln(uint256 value) internal pure returns (uint256) {
        uint256 x = value;
        uint256 LOG = 0;
        while (x >= 1500000) {
            LOG = LOG + 405465;
            x = x * 2 / 3;
        }
        x = x - 1000000;
        uint256 y = x;
        uint256 i = 1;
        while (i < 10) {
            LOG = LOG + (y / i);
            i = i + 1;
            y = y * x / 1000000;
            LOG = LOG - (y / i);
            i = i + 1;
            y = y * x / 1000000;
        }
        
        return LOG;
    }
}
