// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";

contract MockUniswapV3Factory is IUniswapV3Factory {
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override returns (address) {
        return address(0);
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view override returns (address) {
        return address(0);
    }

    function allPools(uint256) external view override returns (address) {
        return address(0);
    }
}
