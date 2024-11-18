// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import { ClvrLibrary } from "./ClvrLibrary.sol";


contract ClvrIntentPool {
    // Mapping from PoolKey to Intents for a pool
    mapping(bytes32 => mapping(bytes32 => ClvrLibrary.CLVRIntent)) public intents;

    constructor() {}

    /**
     * @notice Submit an intent to the signer
     * @param intent The intent to submit
     * @param v The v component of the signature
     * @param r The r component of the signature
     * @param s The s component of the signature
     */
    function submitIntent(ClvrLibrary.CLVRIntent memory intent, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 digest = keccak256(abi.encode(intent));

        // Ensure the intent is valid
        address signer = ecrecover(digest, v, r, s);
        if (signer != intent.creator) {
            revert("Invalid signature");
        }

        bytes32 poolKey = ClvrLibrary.getPoolKey(intent.tokenIn, intent.tokenOut, intent.fee);

        // Store the intent
        // Note: if the intent exists in the mapping, it has been signed already
        intents[poolKey][digest] = intent;
    }

    function intentExists(
        bytes32 poolKey,
        bytes32 intentHash
    ) external view returns (bytes4 magicValue) {
        ClvrLibrary.CLVRIntent memory intent = intents[poolKey][intentHash];
        if (intent.creator == ClvrLibrary.EMPTY_ADDRESS) {
            return ClvrLibrary.INVALID_SIGNATURE;
        }

        return ClvrLibrary.MAGICVALUE;
    }
}
