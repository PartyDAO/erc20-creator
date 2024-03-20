// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
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

    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;
    IUniswapV2Router02 public immutable UNISWAP_V2_ROUTER;
    IUniswapV2Factory public immutable UNISWAP_V2_FACTORY;
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
        IUniswapV2Router02 _uniswapV2Router,
        IUniswapV2Factory _uniswapV2Factory,
        address _weth,
        address _feeRecipient,
        uint16 _feeBasisPoints
    ) {
        TOKEN_DISTRIBUTOR = _tokenDistributor;
        UNISWAP_V2_ROUTER = _uniswapV2Router;
        UNISWAP_V2_FACTORY = _uniswapV2Factory;
        WETH = _weth;
        feeRecipient = _feeRecipient;
        feeBasisPoints = _feeBasisPoints;
    }

    function createToken(
        address partyAddress,
        string calldata name,
        string calldata symbol,
        TokenConfiguration calldata config,
        address recipientAddress
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
        token.approve(address(UNISWAP_V2_ROUTER), config.numTokensForLP);
        UNISWAP_V2_ROUTER.addLiquidityETH{value: numETHForLP}(
            address(token),
            config.numTokensForLP,
            config.numTokensForLP,
            numETHForLP,
            address(0), // Burn LP position
            block.timestamp + 10 minutes
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

    function getPair(address token) external view returns (address) {
        return UNISWAP_V2_FACTORY.getPair(token, WETH);
    }

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
