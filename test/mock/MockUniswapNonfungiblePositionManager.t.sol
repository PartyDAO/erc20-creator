// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {MockUniswapV3Factory} from "./MockUniswapV3Factory.t.sol";
import {IMulticall} from "@uniswap/v3-periphery/interfaces/IMulticall.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETH9} from "./WETH.t.sol";

contract MockUniswapNonfungiblePositionManager is IMulticall {
    WETH9 public immutable WETH;
    MockUniswapV3Factory public immutable FACTORY;

    constructor(address weth, address factory) {
        WETH = WETH9(payable(weth));
        FACTORY = MockUniswapV3Factory(factory);
    }

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address pool = FACTORY.getPool(params.token0, params.token1, params.fee);
        if (params.token0 != address(WETH) || msg.value == 0) {
            IERC20(params.token0).transferFrom(msg.sender, pool, params.amount0Desired);
        } else {
            WETH.deposit{value: params.amount0Desired}();
            WETH.transfer(pool, params.amount0Desired);
        }

        if (params.token1 != address(WETH) || msg.value == 0) {
            IERC20(params.token1).transferFrom(msg.sender, pool, params.amount1Desired);
        } else {
            WETH.deposit{value: params.amount1Desired}();
            WETH.transfer(pool, params.amount1Desired);
        }

        return (1, 0, 0, 0);
    }

    function refundETH() external payable {}

    function multicall(bytes[] calldata calls) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            require(success);
            results[i] = result;
        }
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory callData) external {}
}
