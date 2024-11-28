// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { console } from "forge-std/console.sol";
import { ln } from "@prb-math/ud60x18/Math.sol";
import "../src/ClvrModel.sol";

contract ClvrModelTest is Test {
    ClvrModel public model;

    bool constant BUY = true;
    bool constant SELL = false;

    // setup a model with equal reserves
    function setUp() public {
        model = new ClvrModel(100e18, 100e18);
    }

    function testOrdering() public {
        ClvrHook.SwapParamsExtended[] memory o = new ClvrHook.SwapParamsExtended[](3);
        o[0] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(BUY, -10e18, 0));
        o[1] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -5e18, 0));
        o[2] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -2e18, 0));

        ClvrHook.SwapParamsExtended[] memory candidate = new ClvrHook.SwapParamsExtended[](3);
        candidate[0] = o[2];
        candidate[1] = o[1];
        candidate[2] = o[0];

        require(model.isBetterOrdering(1e18, 100e18, 100e18, o, candidate), "Candidate should be better");
        require(!model.isBetterOrdering(1e18, 100e18, 100e18, candidate, o), "Original should be worse than a candidate ordering");
    }
}