// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import "./../lib/party-protocol/contracts/distribution/ITokenDistributor.sol";
import {GovernableERC20, ERC20} from "./GovernableERC20.sol";

contract ERC20Creator {
    event ERC20Created(
        address indexed token,
        address indexed party,
        address recipient,
        TokenConfiguration config
    );

    event FeeRecipientUpdated(
        address indexed oldFeeRecipient,
        address indexed newFeeRecipient
    );
    event FeeBasisPointsUpdated(
        uint16 oldFeeBasisPoints,
        uint16 newFeeBasisPoints
    );

    error InvalidTokenDistribution();
    error OnlyFeeRecipient();

    uint24 internal constant POOL_FEE = 10_000; // 1% fee
    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;
    INonfungiblePositionManager public immutable UNISWAP_V3_POSITION_MANAGER;
    IUniswapV3Factory public immutable UNISWAP_V3_FACTORY;
    address public immutable WETH;

    address public feeRecipient;
    uint16 public feeBasisPoints;

    struct TokenConfiguration {
        uint256 totalSupply;
        uint256 numTokensForDistribution;
        uint256 numTokensForRecipient;
        uint256 numTokensForLP;
    }

    constructor(
        ITokenDistributor _tokenDistributor,
        INonfungiblePositionManager _uniswapV3PositionManager,
        IUniswapV3Factory _uniswapV3Factory,
        address _weth,
        address _feeRecipient,
        uint16 _feeBasisPoints
    ) {
        TOKEN_DISTRIBUTOR = _tokenDistributor;
        UNISWAP_V3_POSITION_MANAGER = _uniswapV3PositionManager;
        UNISWAP_V3_FACTORY = _uniswapV3Factory;
        WETH = _weth;
        feeRecipient = _feeRecipient;
        feeBasisPoints = _feeBasisPoints;
    }

    function createToken(
        address partyAddress,
        string calldata name,
        string calldata symbol,
        TokenConfiguration calldata config,
        address recipientAddress,
        uint160 sqrtPriceX96
    ) external payable returns (ERC20 token) {
        if (
            config.numTokensForDistribution +
                config.numTokensForRecipient +
                config.numTokensForLP !=
            config.totalSupply
        ) {
            revert InvalidTokenDistribution();
        }

        // Create token
        token = new GovernableERC20(
            name,
            symbol,
            config.totalSupply,
            address(this)
        );

        // Create distribution
        token.transfer(
            address(TOKEN_DISTRIBUTOR),
            config.numTokensForDistribution
        );
        TOKEN_DISTRIBUTOR.createErc20Distribution(
            IERC20(address(token)),
            Party(payable(partyAddress)),
            payable(address(0)),
            0
        );

        // Take fee
        uint256 ethValue = msg.value;
        uint256 feeAmount = (ethValue * feeBasisPoints) / 1e4;
        payable(feeRecipient).transfer(feeAmount);

        // Create locked LP pair
        uint256 numETHForLP = ethValue - feeAmount;

        // Create and initialize pool
        address pool = UNISWAP_V3_FACTORY.createPool(
            WETH,
            address(token),
            POOL_FEE
        );
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        UNISWAP_V3_POSITION_MANAGER.mint{value: numETHForLP}(
            INonfungiblePositionManager.MintParams({
                token0: WETH,
                token1: address(token),
                fee: POOL_FEE,
                tickLower: -887200,
                tickUpper: 887200,
                amount0Desired: numETHForLP,
                amount1Desired: config.numTokensForLP,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(0),
                deadline: block.timestamp
            })
        );

        // Transfer tokens to recipient
        token.transfer(recipientAddress, config.numTokensForRecipient);

        emit ERC20Created(
            address(token),
            partyAddress,
            recipientAddress,
            config
        );
    }

    // function getPair(address token) external view returns (address) {
    //     return UNISWAP_V3_FACTORY.getPair(token, WETH);
    // }

    function setFeeRecipient(address _feeRecipient) external {
        address oldFeeRecipient = feeRecipient;
        if (msg.sender != oldFeeRecipient) revert OnlyFeeRecipient();
        emit FeeRecipientUpdated(oldFeeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setFeeBasisPoints(uint16 _feeBasisPoints) external {
        if (msg.sender != feeRecipient) revert OnlyFeeRecipient();
        emit FeeBasisPointsUpdated(feeBasisPoints, _feeBasisPoints);
        feeBasisPoints = _feeBasisPoints;
    }
}
