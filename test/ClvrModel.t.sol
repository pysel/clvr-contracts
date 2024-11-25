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
    /*
    Box::new(Trade::new(size(5), TradeDirection::Sell)),
    Box::new(Trade::new(size(10), TradeDirection::Buy)),
    Box::new(Trade::new(size(2), TradeDirection::Sell)),
     */
    function testModel() public {
        ClvrHook.SwapParamsExtended[] memory o = new ClvrHook.SwapParamsExtended[](4);
        o[0] = ClvrHook.SwapParamsExtended(address(0), address(0), IPoolManager.SwapParams(false, 0, 0)); // first one is mock (address = 0)
        o[3] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(BUY, -10e18, 0));
        o[1] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -5e18, 0)); 
        o[2] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -2e18, 0)); 

        ClvrHook.SwapParamsExtended[] memory expected = new ClvrHook.SwapParamsExtended[](4);
        expected[0] = ClvrHook.SwapParamsExtended(address(0), address(0), IPoolManager.SwapParams(false, 0, 0));
        expected[1] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -2e18, 0));
        expected[2] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -5e18, 0));
        expected[3] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(BUY, -10e18, 0));

        uint256 gas = gasleft();

        o = model.clvrReorder(1e18, o, 100e18, 100e18);

        console.log("Gas used: ", gas - gasleft());

        for (uint256 i = 0; i < o.length; i++) {
            assertEq(o[i].recepient, expected[i].recepient);
            assertEq(o[i].params.amountSpecified, expected[i].params.amountSpecified);
        }
    }
}