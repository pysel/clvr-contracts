// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { ln } from "@prb-math/ud60x18/Math.sol";
import "../src/ClvrModel.sol";

contract ClvrModelTest is Test {
    ClvrModel public model;

    // setup a model with equal reserves
    function setUp() public {
        model = new ClvrModel(100e18, 100e18);
    }
    function testPGas() public {
        ClvrModel.TradeMinimal[] memory trades = new ClvrModel.TradeMinimal[](3);

        trades[0] = ClvrModel.TradeMinimal(ClvrModel.Direction.Sell, 5e18);
        trades[1] = ClvrModel.TradeMinimal(ClvrModel.Direction.Sell, 2e18);
        trades[2] = ClvrModel.TradeMinimal(ClvrModel.Direction.Buy, 10e18);

        uint256 left = gasleft();

        model.P(trades, 2);

        console.log("Gas used in P: ", left - gasleft());
    }

}