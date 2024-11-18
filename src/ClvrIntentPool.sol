// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import { ClvrLibrary } from "./ClvrLibrary.sol";


contract ClvrIntentPool is IERC1271 {
    struct CLVRIntent {
        address creator;
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 amountIn;
        uint256 deadline;
    }

    // Array of intents
    CLVRIntent[] public intents;

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

        // Store the intent
        // Note: if the intent exists in the array, it has been signed already
        intents.push(intent);
    }

    function isValidSignature(
        bytes32 intentsHash,
        bytes memory
    ) external view override returns (bytes4 magicValue) {
        bytes32 actualHash = keccak256(abi.encode(intents));
        if (actualHash != intentsHash) {
            return ClvrLibrary.INVALID_SIGNATURE;
        }

        return ClvrLibrary.MAGICVALUE;
    }
}
