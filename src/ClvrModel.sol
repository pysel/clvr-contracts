// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

import { ClvrLn } from "./ClvrLn.sol";
import { ClvrHook } from "./ClvrHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";


import { console } from "forge-std/console.sol";

contract ClvrModel {
    using ClvrLn for uint256;
    using SafeCast for *;

    enum Direction {
        Buy,
        Sell,
        NULL
    }

    uint256 public reserveY;
    uint256 public reserveX;

    constructor(uint256 reserve_y, uint256 reserve_x) {
        reserveY = reserve_y;
        reserveX = reserve_x;
    }

    // PUBLIC FUNCTIONS

    function clvrReorder(uint256 p0, 
        ClvrHook.SwapParamsExtended[] memory o, 
        uint256 reserve_x, 
        uint256 reserve_y
    ) public returns (ClvrHook.SwapParamsExtended[] memory) {
        o = addMockTrade(o);

        set_reserve_x(reserve_x);
        set_reserve_y(reserve_y);

        int128 lnP0 = p0.lnU256().toInt128();
        uint256 cachedY = reserveY;
        uint256 cachedX = reserveX;

        for (uint256 i = 1; i < o.length; ) {
            uint256 candidateIndex = i;
            (uint256 p, uint256 y_cached, uint256 x_cached) = P_cached(o, i, cachedY, cachedX);

            int256 unsquaredCandidateValue = lnP0 - p.lnU256().toInt128();
            int256 candidateValue = unsquaredCandidateValue ** 2 / 1e18;

            for (uint256 j = i + 1; j < o.length; ) {
                swap(o, i, j); // try the next element at position i
                
                (uint256 p_new, uint256 y_cached_new, uint256 x_cached_new) = P_cached(o, i, cachedY, cachedX);

                int256 unsquaredNewValue = lnP0 - p_new.lnU256().toInt128();
                int256 newCandidateValue = unsquaredNewValue ** 2 / 1e18;

                if (newCandidateValue < candidateValue) {
                    candidateIndex = j;
                    candidateValue = newCandidateValue;

                    y_cached = y_cached_new;
                    x_cached = x_cached_new;
                }

                swap(o, j, i); // swap back

                unchecked {
                    j++;
                }
            }

            if (candidateIndex != i) {
                swap(o, i, candidateIndex);
            }

            cachedY = y_cached;
            cachedX = x_cached;

            unchecked {
                i++;
            }
        }

        // TODO: there must be a better way to do this
        ClvrHook.SwapParamsExtended[] memory result = new ClvrHook.SwapParamsExtended[](o.length - 1);
        for (uint256 i = 1; i < o.length; i++) {
            result[i - 1] = o[i];
        }

        return result;
    }

    // adds a mock trade as a first entry of th array
    function addMockTrade(ClvrHook.SwapParamsExtended[] memory o) internal pure returns(ClvrHook.SwapParamsExtended[] memory) {
        ClvrHook.SwapParamsExtended memory mock = ClvrHook.SwapParamsExtended(address(0), address(0), IPoolManager.SwapParams(false, 0, 0));
        ClvrHook.SwapParamsExtended[] memory newO = new ClvrHook.SwapParamsExtended[](o.length + 1);
        for (uint256 i = 0; i < o.length; i++) {
            newO[i] = o[i];
        }
        newO[o.length] = o[0];
        newO[0] = mock;
        return newO;
    }

    function swap(ClvrHook.SwapParamsExtended[] memory o, uint256 i1, uint256 i2) internal pure {
        ClvrHook.SwapParamsExtended memory temp = o[i1];
        o[i1] = o[i2];
        o[i2] = temp;
    }

    function set_reserve_x(uint256 reserve_x) internal {
        reserveX = reserve_x;
    }

    function set_reserve_y(uint256 reserve_y) internal {
        reserveY = reserve_y;
    }

    // INTERNAL FUNCTIONS

    function y_out_cached(ClvrHook.SwapParamsExtended[] memory o, uint256 i, uint256 cachedY, uint256 cachedX) private pure returns (uint256) {
        if (direction(o[i]) == Direction.Sell) {
            uint256 fraction = cachedY / (cachedX + amountIn(o[i]));
            return fraction * amountIn(o[i]);
        }

        return 0;
    }

    function x_out_cached(ClvrHook.SwapParamsExtended[] memory o, uint256 i, uint256 cachedY, uint256 cachedX) private pure returns (uint256) {
        if (direction(o[i]) == Direction.Buy) {
            uint256 fraction = cachedX / (cachedY + amountIn(o[i]));
            return fraction * amountIn(o[i]);
        }
        return 0;
    }

    function Y_cached(ClvrHook.SwapParamsExtended[] memory o, uint256 i, uint256 cachedY, uint256 cachedX) private view returns (uint256) {
        if (i == 0) {
            return reserveY;
        } else if (i > 0 && direction(o[i]) == Direction.Buy) {
            return cachedY + amountIn(o[i]);
        } else if (i > 0 && direction(o[i]) == Direction.Sell) {
            return cachedY - y_out_cached(o, i, cachedY, cachedX);
        }
        revert("Invalid call to Y_cached");
    }

    function X_cached(ClvrHook.SwapParamsExtended[] memory o, uint256 i, uint256 cachedY, uint256 cachedX) private view returns (uint256) {
        if (i == 0) {
            return reserveX;
        } else if (i > 0 && direction(o[i]) == Direction.Sell) {
            return cachedX + amountIn(o[i]);
        } else if (i > 0 && direction(o[i]) == Direction.Buy) {
            return cachedX - x_out_cached(o, i, cachedY, cachedX);
        }
        revert("Invalid call to X_cached");
    }

    /// @notice Returns the price, the new y and the new x after the swap
    function P_cached(ClvrHook.SwapParamsExtended[] memory o, uint256 i, uint256 cachedY, uint256 cachedX) private view returns (uint256, uint256, uint256) {
        uint256 y_cached_new = Y_cached(o, i, cachedY, cachedX);
        uint256 x_cached_new = X_cached(o, i, cachedY, cachedX);
        return (y_cached_new * 1e18 / x_cached_new, y_cached_new, x_cached_new);
    }

    function direction(ClvrHook.SwapParamsExtended memory o) private pure returns (Direction) {
        if (o.recepient == address(0)) {
            return Direction.NULL;
        }

        return o.params.zeroForOne ? Direction.Buy : Direction.Sell;
    }

    function amountIn(ClvrHook.SwapParamsExtended memory o) private pure returns (uint256) {
        return uint256(-o.params.amountSpecified);
    }
}