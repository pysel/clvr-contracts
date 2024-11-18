// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { ln } from "@prb-math/ud60x18/Math.sol";
import { UD60x18, ud } from "@prb-math/UD60x18.sol";
import "../src/ClvrLibrary.sol";

contract ClvrLibraryTest is Test {
    function setUp() public {
        //
    }

    function testLn() public pure {
        // ln(ud(1e18 + 1e17)).unwrap();
        assertEq(ln(ud(1e18 + 1e17)).unwrap(), 95310179804324849);
    }
}