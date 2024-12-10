// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {QuickSort} from "../src/Sort.sol";
import { console } from "forge-std/console.sol";

contract SortTest is Test {
    QuickSort public quickSort;

    function setUp() public {
        quickSort = new QuickSort();
    }

    function testSort() public {
        for (uint256 i = 10; i <= 400; i+=10) {
            runSort(i);
        }
    }

    function runSort(uint256 size) public {
        uint[] memory data = new uint[](size);
        for (uint256 i = 0; i < size; i++) {
            data[i] = i % 3;
        }

        uint256 gas = gasleft();
        quickSort.sort(data);
        console.log("Gas (in dollars) used for array of size ", size, " gas: ", gas - gasleft());
    }

    function gasToDollars(uint256 gas) internal pure returns (uint256) {
        return gas * 1e9 * 30000 / 1e18;
    }
}   
