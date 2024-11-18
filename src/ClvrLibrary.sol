pragma solidity ^0.8.24;

import { ClvrIntentPool } from "./ClvrIntentPool.sol";

library ClvrLibrary {
    address internal constant EMPTY_ADDRESS = address(0);
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant INVALID_SIGNATURE = ~MAGICVALUE;
}
