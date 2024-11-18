// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/ClvrLibrary.sol";

contract ClvrLibraryTest {
    function testLn() public {
        assertEq(ClvrLibrary.ln(1000000), 1381551);
    }
}