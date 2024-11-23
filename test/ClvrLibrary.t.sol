// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { ln } from "@prb-math/ud60x18/Math.sol";
import { UD60x18, ud } from "@prb-math/UD60x18.sol";
import { ClvrLn } from "../src/ClvrLn.sol";

contract ClvrLibraryTest is Test {
    using ClvrLn for uint256;

    function setUp() public {}

    function testLn() public pure {
        uint256 x = 1e18;
        console.log(x.lnU256());
    }
}