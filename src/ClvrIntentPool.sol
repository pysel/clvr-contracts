// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import { ClvrLibrary } from "./ClvrLibrary.sol";


contract ClvrIntentPool is IERC1271 {
    // Mapping of intents from bytes32 hash to intent itself
    mapping(bytes32 => ClvrLibrary.CLVRIntent) public intents;

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

        // Store the intent
        // Note: if the intent exists in the mapping, it has been signed already
        intents[digest] = intent;
    }

    function isValidSignature(
        bytes32 intentHash,
        bytes memory
    ) external pure override returns (bytes4 magicValue) {
        bytes32 actualHash = keccak256(abi.encode(intentHash));
        if (actualHash != intentHash) {
            return ClvrLibrary.INVALID_SIGNATURE;
        }

        return ClvrLibrary.MAGICVALUE;
    }
}
