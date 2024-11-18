// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ClvrLibrary.sol";

contract ClvrLibraryTest is Test {
    function setUp() public {
        //
    }

    function testLn() public {
        assertEq(ClvrLibrary.ln(1000000), 1381551);
    }
}