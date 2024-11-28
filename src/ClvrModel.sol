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

    modifier equalLength(ClvrHook.SwapParamsExtended[] memory o1, ClvrHook.SwapParamsExtended[] memory o2) {
        require(o1.length == o2.length, "Orderings must be of the same length");
        _;
    }


    constructor(uint256 reserve_y, uint256 reserve_x) {
        reserveY = reserve_y;
        reserveX = reserve_x;
    }

    // PUBLIC FUNCTIONS
    
    /// @notice Checks if the candidate ordering is better than the challenged ordering
    /// @notice Candidate ordering is better if the CLVR value is lower at any step
    /// @param p0 The initial price
    /// @param reserve_x The initial reserve x
    /// @param reserve_y The initial reserve y
    /// @param challengedOrdering The ordering to be challenged
    /// @param candidateOrdering The ordering to be checked
    /// @return True if the candidate ordering is better, false otherwise
    function isBetterOrdering(
        uint256 p0, 
        uint256 reserve_y,
        uint256 reserve_x,
        ClvrHook.SwapParamsExtended[] memory challengedOrdering, 
        ClvrHook.SwapParamsExtended[] memory candidateOrdering
    ) 
        public 
        equalLength(challengedOrdering, candidateOrdering) 
        returns (bool) 
    {
        set_reserve_y(reserve_y);
        set_reserve_x(reserve_x);

        challengedOrdering = addMockTrade(challengedOrdering);
        candidateOrdering = addMockTrade(candidateOrdering);

        int256 ln_p0 = p0.lnU256().toInt256();

        uint256[] memory challengedVolatility = new uint256[](challengedOrdering.length);
        uint256[] memory candidateVolatility = new uint256[](candidateOrdering.length);

        uint256 cachedY = reserveY;
        uint256 cachedX = reserveX;

        for (uint256 i = 1; i < challengedOrdering.length; i++) {
            (uint256 p, uint256 cached_y, uint256 cached_x) = P_cached(challengedOrdering, i, cachedY, cachedX);
            int256 ln_p = p.lnU256().toInt256();
            int256 diff = ln_p0 - ln_p;
            challengedVolatility[i] = uint256(diff ** 2 / 1e18);

            cachedY = cached_y;
            cachedX = cached_x;
        }

        cachedY = reserveY;
        cachedX = reserveX;

        for (uint256 i = 1; i < candidateOrdering.length; i++) {
            (uint256 p, uint256 cached_y, uint256 cached_x) = P_cached(candidateOrdering, i, cachedY, cachedX);
            int256 ln_p = p.lnU256().toInt256();
            int256 diff = ln_p0 - ln_p;
            candidateVolatility[i] = uint256(diff ** 2 / 1e18);

            cachedY = cached_y;
            cachedX = cached_x;
        }
        
        for (uint256 i = 0; i < challengedOrdering.length; i++) {
            if (candidateVolatility[i] < challengedVolatility[i]) {
                return true;
            }
        }

        return false;
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

    // CONTRACT: note in TradeMinimal implemented!
    function P(ClvrHook.SwapParamsExtended[] memory o, uint256 i) public view returns (uint256) {
        uint256 base = 1e18;
        return Y(o, i) * base / X(o, i);
    }

    function set_reserve_x(uint256 reserve_x) internal {
        reserveX = reserve_x;
    }

    function set_reserve_y(uint256 reserve_y) internal {
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