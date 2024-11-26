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
    /// @param challengedOrdering The ordering to be challenged
    /// @param candidateOrdering The ordering to be checked
    /// @return True if the candidate ordering is better, false otherwise
    function isBetterOrdering(uint256 p0, ClvrHook.SwapParamsExtended[] memory challengedOrdering, ClvrHook.SwapParamsExtended[] memory candidateOrdering) 
        public 
        view 
        equalLength(challengedOrdering, candidateOrdering) 
        returns (bool) 
    {
        challengedOrdering = addMockTrade(challengedOrdering);
        candidateOrdering = addMockTrade(candidateOrdering);

        int128 lnP0 = p0.lnU256().toInt128();
        for (uint256 i = 1; i < challengedOrdering.length; i++) {
            int128 unsquaredChallengedValue = lnP0 - P(challengedOrdering, i).lnU256().toInt128();
            int256 challengedValue = unsquaredChallengedValue ** 2 / 1e18;

            int128 unsquaredCandidateValue = lnP0 - P(candidateOrdering, i).lnU256().toInt128();
            int256 candidateValue = unsquaredCandidateValue ** 2 / 1e18;

            // the candidate ordering is better because the value is lower
            if (candidateValue < challengedValue) {
                return true;
            }
        }

        return false;
    }

    function clvrReorder(uint256 p0, 
        ClvrHook.SwapParamsExtended[] memory o, 
        uint256 reserve_x, 
        uint256 reserve_y
    ) public returns (ClvrHook.SwapParamsExtended[] memory) {
        o = addMockTrade(o);

        set_reserve_x(reserve_x);
        set_reserve_y(reserve_y);

        int128 lnP0 = p0.lnU256().toInt128();
        for (uint256 i = 1; i < o.length; ) {
            uint256 candidateIndex = i;
            int128 unsquaredCandidateValue = lnP0 - P(o, i).lnU256().toInt128();
            int256 candidateValue = unsquaredCandidateValue ** 2 / 1e18;

            for (uint256 j = i + 1; j < o.length; ) {
                swap(o, i, j);

                int256 unsquaredValue = lnP0 - P(o, i).lnU256().toInt128();
                int256 value = unsquaredValue ** 2 / 1e18;

                if (value < candidateValue) {
                    candidateIndex = j;
                    candidateValue = value;
                }

                swap(o, j, i);

                unchecked {
                    j++;
                }
            }

            if (candidateIndex != i) {
                swap(o, i, candidateIndex);
            }

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