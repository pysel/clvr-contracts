// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ln } from "@prb-math/ud60x18/Math.sol";
import { UD60x18, ud } from "@prb-math/UD60x18.sol";
import { console } from "forge-std/console.sol";

/// @notice A clvr library to efficiently compute RELATIVE natural logarithms
/// By relative, we mean that it computes not the ln(x) but ln(x * 1e18), hence, it is suitable for checking differences
/// between natural logarithms of two numbers, but not suitable for concrete ln computations.
/// @dev not an actual natural log
library ClvrLn {
    /// @notice Computes ln(x * 1e18)
    /// @param x The number to compute the natural logarithm of
    /// @return The natural logarithm of x * 1e18
    function lnU256(uint256 x) public pure returns (uint256) {
        uint256 appendedX = x * 1e18;
        uint256 natlog1e18 = ln(ud(appendedX)).unwrap();
        return natlog1e18;
    }
}

