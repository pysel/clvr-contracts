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
        ClvrHook.SwapParamsExtended[] memory o = new ClvrHook.SwapParamsExtended[](3);
        o[2] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(BUY, -10e18, 0));
        o[0] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -5e18, 0)); 
        o[1] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -2e18, 0)); 

        ClvrHook.SwapParamsExtended[] memory expected = new ClvrHook.SwapParamsExtended[](3);
        expected[0] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -2e18, 0));
        expected[1] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(SELL, -5e18, 0));
        expected[2] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(BUY, -10e18, 0));

        uint256 gas = gasleft();

        o = model.clvrReorder(1e18, o, 100e18, 100e18);

        console.log("Gas used: ", gas - gasleft());

        for (uint256 i = 0; i < o.length; i++) {
            assertEq(o[i].recepient, expected[i].recepient);
            assertEq(o[i].params.amountSpecified, expected[i].params.amountSpecified);
        }
    }

    function testModelGasConsumption() public {
        for (uint256 i = 10; i <= 400; i += 10) {
            runSwaps(i);
        }
    }

    function runSwaps(uint256 swaps) internal {
        ClvrHook.SwapParamsExtended[] memory o = new ClvrHook.SwapParamsExtended[](swaps);

        // create `swaps` alternating buys and sells
        for (uint256 i = 0; i < swaps; i++) {
            bool direction = i % 2 == 0 ? BUY : SELL;
            o[i] = ClvrHook.SwapParamsExtended(address(1), address(1), IPoolManager.SwapParams(direction, -10e18, 0));
        }

        uint256 gas = gasleft();
        o = model.clvrReorder(1e18, o, 100e18, 100e18);
        console.log("Gas (in dollars) used for ", swaps, " swaps: ", gasToDollars(gas - gasleft()));
    }

    function gasToDollars(uint256 gas) internal pure returns (uint256) {
        return gas * 1e9 * 30000 / 1e18;
    }
}