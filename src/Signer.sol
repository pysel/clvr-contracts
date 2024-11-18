// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract CLVRSigner {
    struct CLVRIntent {
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 amountIn;
        uint256 deadline;
        // uint256 salt; // Used to prevent replay attacks, similar to nonce
    }

    // Mapping of hashes to intents
    mapping(bytes32 => CLVRIntent) public intents;

    constructor() {
    }

    /**
     * @notice Submit an intent to the signer
     * @param intent The intent to submit
     * @param signature The signature of the hash of the intent
     */
    function submitIntent(CLVRIntent memory intent, bytes32 signature) public {
        
    }
}
