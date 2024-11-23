// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ln } from "@prb-math/ud60x18/Math.sol";
import { UD60x18, ud } from "@prb-math/UD60x18.sol";
import { console } from "forge-std/console.sol";

import { ClvrIntentPool } from "./ClvrIntentPool.sol";

// NOT AN ACTUAL NATURAL LOG
library ClvrLn {
    // ln only takes >1e18 uints, hence use property:
    // ln(a) = ln(a * 1e18 / 1e18) = ln(a * 1e18) - ln(1e18)
    function lnU256(uint256 x) public pure returns (uint256) {
        uint256 appendedX = x * 1e18;
        uint256 natlog1e18 = ln(ud(appendedX)).unwrap();
        return natlog1e18;
    }
}

