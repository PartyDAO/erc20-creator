// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {WETH9} from "./WETH.t.sol";
import {MockUniswapV3Factory} from "./MockUniswapV3Factory.t.sol";
import {MockUniswapNonfungiblePositionManager} from "./MockUniswapNonfungiblePositionManager.t.sol";

abstract contract MockUniswapV3Deployer {
    struct UniswapV3Deployment {
        address payable WETH;
        address FACTORY;
        address POSITION_MANAGER;
    }

    function _deployUniswapV3() internal returns (UniswapV3Deployment memory deployment) {
        deployment.WETH = payable(new WETH9());
        deployment.FACTORY = address(new MockUniswapV3Factory());
        deployment.POSITION_MANAGER =
            address(new MockUniswapNonfungiblePositionManager(deployment.WETH, deployment.FACTORY));
    }
}
