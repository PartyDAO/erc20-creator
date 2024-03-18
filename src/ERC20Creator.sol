// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./GovernableERC20.sol";

contract ERC20Creator {
    address public feeRecipient;
    uint256 public feeBasisPoints;

    IUniswapV2Router02 public immutable uniswapV2Router;

    struct TokenConfiguration {
        uint256 totalSupply;
        uint256 numTokensForDistribution;
        uint256 numTokensForRecipient;
        uint256 numTokensForLP;
    }

    constructor(
        address _uniswapV2Router,
        address _feeRecipient,
        uint256 _feeBasisPoints
    ) {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
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
        require(
            config.numTokensForDistribution +
                config.numTokensForRecipient +
                config.numTokensForLP ==
                config.totalSupply,
            "Invalid token distribution"
        );
        token = new GovernableERC20(
            name,
            symbol,
            config.totalSupply,
            address(this)
        );
        // distribute tokens to recipient
        token.transfer(recipientAddress, config.numTokensForRecipient);

        // distribute tokens to party
        token.transfer(partyAddress, config.numTokensForDistribution);

        // create the LP

        // uint256 ethValue = msg.value;
        // uint256 feeAmount = (ethValue * feeBasisPoints) / 10000;
        // uint256 liquidityEthAmount = ethValue - feeAmount;
        // token.approve(address(uniswapV2Router), numTokensForLP);
        // (
        //     uint256 amountToken,
        //     uint256 amountETH,
        //     uint256 liquidity
        // ) = uniswapV2Router.addLiquidityETH{value: liquidityEthAmount}(
        //         address(token),
        //         numTokensForLP,
        //         0,
        //         0,
        //         address(this),
        //         block.timestamp
        //     );
    }

    function setFeeRecipient(address _feeRecipient) external {
        require(msg.sender == feeRecipient, "Only fee recipient can update");
        feeRecipient = _feeRecipient;
    }

    function setFeeBasisPoints(uint256 _feeBasisPoints) external {
        require(msg.sender == feeRecipient, "Only fee recipient can update");
        feeBasisPoints = _feeBasisPoints;
    }
}
