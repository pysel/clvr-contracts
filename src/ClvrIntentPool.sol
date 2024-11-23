// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";


contract ClvrIntentPool {
    struct CLVRIntent {
        address creator;
        address tokenIn;
        address tokenOut;
        address recipient;
        uint24 fee;
        uint256 amountIn;
        uint256 deadline;
    }

    // Mapping from PoolKey to Intents for a pool
    mapping(bytes32 => mapping(bytes32 => CLVRIntent)) public intents;

    address internal constant EMPTY_ADDRESS = address(0);
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant INVALID_SIGNATURE = ~MAGICVALUE;

    constructor() {}

    /**
     * @notice Submit an intent to the signer
     * @param intent The intent to submit
     * @param v The v component of the signature
     * @param r The r component of the signature
     * @param s The s component of the signature
     */
    function submitIntent(CLVRIntent memory intent, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 digest = keccak256(abi.encode(intent));

        // Ensure the intent is valid
        address signer = ecrecover(digest, v, r, s);
        if (signer != intent.creator) {
            revert("Invalid signature");
        }

        bytes32 poolKey = getPoolKey(intent.tokenIn, intent.tokenOut, intent.fee);

        // Store the intent
        // Note: if the intent exists in the mapping, it has been signed already
        intents[poolKey][digest] = intent;
    }

    function getPoolKey(address tokenIn, address tokenOut, uint24 fee) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenIn, tokenOut, fee));
    }

    function intentExists(
        bytes32 poolKey,
        bytes32 intentHash
    ) external view returns (bytes4 magicValue) {
        CLVRIntent memory intent = intents[poolKey][intentHash];
        if (intent.creator == EMPTY_ADDRESS) {
            return INVALID_SIGNATURE;
        }

        return MAGICVALUE;
    }
}
