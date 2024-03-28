// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IERC721Receiver} from "openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IWETH} from "../lib/v2-periphery/contracts/interfaces/IWETH.sol";
import {Party} from "party-protocol/contracts/party/Party.sol";
import {ITokenDistributor, IERC20} from "party-protocol/contracts/distribution/ITokenDistributor.sol";

// Goal: Earn revenue on the volume of the token, not just the initial LP creation

// - Distribute fees to Party
// - Take a 10% fee off the top for PartyDAO

contract FeeCollector is IERC721Receiver {
    INonfungiblePositionManager public immutable POSITION_MANAGER;
    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;
    address payable public immutable PARTY_DAO;
    IWETH public immutable WETH;

    ITokenDistributor public tokenDistributor;
    uint16 public feeBps;

    mapping(ERC20 token => Party party) public tokenToParty;

    constructor(
        INonfungiblePositionManager _positionManager,
        ITokenDistributor _tokenDistributor,
        address payable _partyDao,
        IWETH _weth
    ) {
        POSITION_MANAGER = _positionManager;
        TOKEN_DISTRIBUTOR = _tokenDistributor;
        PARTY_DAO = _partyDao;
        WETH = _weth;
    }

    function collectAndDistributeFees(
        ERC20 token,
        uint256 positionTokenId
    ) external returns (uint256 ethAmount, uint256 tokenAmount) {
        // Collect fees from the LP position
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: address(this),
                // Set amount0Max and amount1Max to max to collect all fees
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (uint256 amount0, uint256 amount1) = POSITION_MANAGER.collect(params);

        (, , address token0, address token1, , , , , , , , ) = POSITION_MANAGER
            .positions(positionTokenId);

        if (token0 == address(token)) {
            tokenAmount = amount0;
            ethAmount = amount1;
        } else if (token1 == address(token)) {
            tokenAmount = amount1;
            ethAmount = amount0;
        } else {
            revert("Invalid pair");
        }

        // Convert WETH to ETH
        WETH.withdraw(ethAmount);

        // Take fee on ETH from the LP position
        uint256 fee = (ethAmount * feeBps) / 1e4;

        // Send fee to PartyDAO
        PARTY_DAO.call{value: fee}("");

        Party party = tokenToParty[token];

        // Distribute token fees to Party
        token.transfer(address(TOKEN_DISTRIBUTOR), tokenAmount);
        TOKEN_DISTRIBUTOR.createErc20Distribution(
            IERC20(address(token)),
            Party(payable(party)),
            payable(address(0)),
            0
        );

        TOKEN_DISTRIBUTOR.createNativeDistribution{value: ethAmount - fee}(
            Party(payable(party)),
            payable(address(0)),
            0
        );
    }

    function setFeeBps(uint16 _feeBps) external {
        require(msg.sender == PARTY_DAO, "Only PartyDAO can set fee");
        feeBps = _feeBps;
    }

    function setTokenDistributor(ITokenDistributor _tokenDistributor) external {
        require(msg.sender == PARTY_DAO, "Only PartyDAO can set distributor");
        tokenDistributor = _tokenDistributor;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        Party party = abi.decode(data, (Party));
        tokenToParty[ERC20(msg.sender)] = party;
        return this.onERC721Received.selector;
    }
}
