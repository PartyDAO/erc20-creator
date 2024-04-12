// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {MockPool} from "./MockPool.t.sol";

contract MockUniswapV3Factory is IUniswapV3Factory {
    mapping(address => mapping(address => mapping(uint24 => address)))
        internal pools;

    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override returns (address pool) {
        pool = address(
            new MockPool{
                salt: keccak256(abi.encodePacked(tokenA, tokenB, fee))
            }()
        );
        pools[tokenA][tokenB][fee] = pool;
        pools[tokenB][tokenA][fee] = pool;
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view override returns (address) {
        return pools[tokenA][tokenB][fee];
    }

    function setOwner(address _owner) external {}
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external {}
    function feeAmountTickSpacing(uint24 fee) external view returns (int24) {
        return 100;
    }
    function owner() external view returns (address) {}
}
