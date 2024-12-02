// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Constants {
    address public constant POOL_MANAGER_SEPOLIA = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    address public constant SWAP_ROUTER_SEPOLIA = 0xe49d2815C231826caB58017e214Bed19fE1c2dD4;

    address public constant CURRENCY1 = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // link
    address public constant CURRENCY0 = 0x0000000000000000000000000000000000000000; // native eth
    uint24 public constant POOL_FEE = 3000;
    int24 public constant TICK_SPACING = 60;
    address public constant HOOK_CONTRACT = 0xA539b90b0bee1EBd567B43B6007d1790028d00A8;

    uint160 public constant STARTING_PRICE_SQRT_X96 = 1.02010509675 * 10e31; // sqrt(3300/23) * 2 ** 96
}

