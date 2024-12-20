// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ClvrHook} from "../src/ClvrHook.sol";
import {ClvrSlashing} from "../src/ClvrSlashing.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "./HookMiner.sol";
import {Constants} from "./Constants.sol";
contract DeployClvrHookOnSepolia is Script, Constants {
    address public hookAddress;
    bytes32 public salt;

    address public deployer;

    function setUp() external {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(deployer != address(0), "DeployClvrHookOnSepolia: DEPLOYER_ADDRESS not set");

    }

    function run() external {
        uint160 targetFlags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        bytes memory constructorArgs = abi.encode(PoolManager(POOL_MANAGER_SEPOLIA), PoolSwapTest(SWAP_ROUTER_SEPOLIA));

        (hookAddress, salt) = HookMiner.find(0x4e59b44847b379578588920cA78FbF26c0B4956C, targetFlags, type(ClvrHook).creationCode, constructorArgs);

        vm.broadcast();

        ClvrHook hook = new ClvrHook{salt: salt}(PoolManager(POOL_MANAGER_SEPOLIA), PoolSwapTest(SWAP_ROUTER_SEPOLIA));
        require(address(hook) == hookAddress, "DeployClvrHookOnSepolia: hook address mismatch");

        console.log("Hook address:", hookAddress);
    }
}
