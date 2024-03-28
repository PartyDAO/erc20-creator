// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";
import {MockUniswapV3Deployer} from "./mock/MockUniswapV3Deployer.t.sol";
import {ERC20CreatorV3} from "src/ERC20CreatorV3.sol";
import {ITokenDistributor} from "party-protocol/contracts/distribution/ITokenDistributor.sol";
import {MockTokenDistributor} from "./mock/MockTokenDistributor.t.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";

contract ERC20CreatorV3Test is Test, MockUniswapV3Deployer {
    UniswapV3Deployment internal uniswap;
    ERC20CreatorV3 internal creator;
    ITokenDistributor internal distributor;

    function setUp() external {
        uniswap = _deployUniswapV3();
        distributor = ITokenDistributor(address(new MockTokenDistributor()));

        creator = new ERC20CreatorV3(
            distributor,
            INonfungiblePositionManager(uniswap.POSITION_MANAGER),
            IUniswapV3Factory(uniswap.FACTORY),
            uniswap.WETH,
            address(this),
            100
        );
    }
}
