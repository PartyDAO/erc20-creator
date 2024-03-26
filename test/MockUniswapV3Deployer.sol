// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {WETH9} from "./vendor/WETH.t.sol";
import {UniswapV3Factory} from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import {NonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/NonfungiblePositionManager.sol";

abstract contract UniswapV3Deployer {
    struct UniswapV3Deployment {
        address WETH;
        address FACTORY;
        address POSITION_MANAGER;
    }
    function _deployUniswapV3()
        internal
        returns (UniswapV3Deployment memory deployment)
    {
        deployment.WETH = address(new WETH9());
        deployment.FACTORY = address(new UniswapV3Factory());
        deployment.POSITION_MANAGER = new NonfungiblePositionManager(
            deployment.FACTORY,
            deployment.WETH,
            address(0)
        );
    }
}
