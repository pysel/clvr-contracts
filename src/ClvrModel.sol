// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ClvrLn } from "./ClvrLn.sol";
import { ClvrHook } from "./ClvrHook.sol";

contract ClvrModel {
    using ClvrLn for uint256;

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

    function clvrReorder(uint256 p0, ClvrHook.SwapParamsExtended[] memory o) view public {
        for (uint256 i = 1; i < o.length; i++) {
            uint256 candidateIndex = i;
            uint256 unsquaredCandidateValue = p0.lnU256() - P(o, i).lnU256();
            uint256 candidateValue = unsquaredCandidateValue ** 2;

            for (uint256 j = i + 1; j < o.length; j++) {
                swap(o, i, j);

                uint256 unsquaredValue = p0.lnU256() - P(o, i).lnU256();
                uint256 value = unsquaredValue ** 2;

                if (value < candidateValue) {
                    candidateIndex = j;
                    candidateValue = value;
                }

                swap(o, j, i);
            }

            if (candidateIndex != i) {
                swap(o, i, candidateIndex);
            }
        }
    }

    function swap(ClvrHook.SwapParamsExtended[] memory o, uint256 i1, uint256 i2) internal view {
        ClvrHook.SwapParamsExtended memory temp = o[i1];
        o[i1] = o[i2];
        o[i2] = temp;
    }

    // CONTRACT: note in TradeMinimal implemented!
    function P(ClvrHook.SwapParamsExtended[] memory o, uint256 i) public view returns (uint256) {
        uint256 base = 1e18;
        return Y(o, i) * base / X(o, i);
    }

    function set_reserve_x(uint256 reserve_x) public {
        reserveX = reserve_x;
    }

    function set_reserve_y(uint256 reserve_y) public {
        reserveY = reserve_y;
    }

    // INTERNAL FUNCTIONS

    function y_out(ClvrHook.SwapParamsExtended[] memory o, uint256 i) private view returns (uint256) {
        if (direction(o[i]) == Direction.Sell) {
            uint256 fraction = Y(o, i - 1) / (X(o, i - 1) + amountIn(o[i]));
            return fraction * amountIn(o[i]);
        }
        return 0;
    }

    function x_out(ClvrHook.SwapParamsExtended[] memory o, uint256 i) private view returns (uint256) {
        if (direction(o[i]) == Direction.Buy) {
            uint256 fraction = X(o, i - 1) / (Y(o, i - 1) + amountIn(o[i]));
            return fraction * amountIn(o[i]);
        }
        return 0;
    }

    function Y(ClvrHook.SwapParamsExtended[] memory o, uint256 i) private view returns (uint256) {
        if (i == 0) {
            return reserveY;
        } else if (i > 0 && direction(o[i]) == Direction.Buy) {
            return Y(o, i - 1) + amountIn(o[i]);
        } else if (i > 0 && direction(o[i]) == Direction.Sell) {
            return Y(o, i - 1) - y_out(o, i);
        }
        revert("Invalid call to Y");
    }

    function X(ClvrHook.SwapParamsExtended[] memory o, uint256 i) private view returns (uint256) {
        if (i == 0) {
            return reserveX;
        } else if (i > 0 && direction(o[i]) == Direction.Sell) {
            return X(o, i - 1) + amountIn(o[i]);
        } else if (i > 0 && direction(o[i]) == Direction.Buy) {
            return X(o, i - 1) - x_out(o, i);
        }
        revert("Invalid call to X");
    }

    function direction(ClvrHook.SwapParamsExtended memory o) private view returns (Direction) {
        return o.params.zeroForOne ? Direction.Buy : Direction.Sell;
    }

    function amountIn(ClvrHook.SwapParamsExtended memory o) private view returns (uint256) {
        return uint256(-o.params.amountSpecified);
    }
}