// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IERC721Receiver} from "openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IWETH} from "../lib/v2-periphery/contracts/interfaces/IWETH.sol";
import {Party} from "party-protocol/contracts/party/Party.sol";
import {ITokenDistributor, IERC20} from "party-protocol/contracts/distribution/ITokenDistributor.sol";

contract FeeCollector is IERC721Receiver {
    struct FeeRecipient {
        address recipient;
        uint16 percentageBps;
    }

    struct PositionData {
        Party party;
        uint40 lastCollectTimestamp;
        bool isFirstRecipientDistributor;
        FeeRecipient[] recipients;
    }

    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;
    address payable public immutable PARTY_DAO;
    IWETH public immutable WETH;

    ITokenDistributor public tokenDistributor;
    uint16 public partyDaoFeeBps;
    uint256 public collectCooldown = 7 days;

    mapping(uint256 tokenId => PositionData) public positionData;

    constructor(
        ITokenDistributor _tokenDistributor,
        address payable _partyDao,
        IWETH _weth
    ) {
        TOKEN_DISTRIBUTOR = _tokenDistributor;
        PARTY_DAO = _partyDao;
        WETH = _weth;
    }

    function collectAndDistributeFees(
        INonfungiblePositionManager position,
        uint256 positionTokenId
    ) external returns (uint256 ethAmount, uint256 tokenAmount) {
        PositionData storage data = positionData[positionTokenId];
        require(
            block.timestamp >= data.lastCollectTimestamp + collectCooldown,
            "Cooldown not over"
        );
        data.lastCollectTimestamp = uint40(block.timestamp);

        // Collect fees from the LP position
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (uint256 amount0, uint256 amount1) = position.collect(params);

        (, , address token0, address token1, , , , , , , , ) = position
            .positions(positionTokenId);

        ERC20 token;
        if (token0 == address(WETH)) {
            token = ERC20(token1);
            ethAmount = amount0;
            tokenAmount = amount1;
        } else if (token1 == address(WETH)) {
            token = ERC20(token0);
            ethAmount = amount1;
            tokenAmount = amount0;
        } else {
            revert("Invalid LP position");
        }

        // Convert WETH to ETH
        WETH.withdraw(ethAmount);

        // Take PartyDAO fee on ETH from the LP position
        uint256 partyDaoFee = (ethAmount * partyDaoFeeBps) / 1e4;
        PARTY_DAO.call{value: partyDaoFee, gas: 100_000}("");

        // Distribute ETH fees to recipients
        uint256 remainingEthFees = ethAmount - partyDaoFee;
        for (uint256 i = 0; i < data.recipients.length; i++) {
            FeeRecipient memory recipient = data.recipients[i];
            uint256 recipientFee = (remainingEthFees *
                recipient.percentageBps) / 1e4;
            if (data.isFirstRecipientDistributor && i == 0) {
                TOKEN_DISTRIBUTOR.createNativeDistribution{value: recipientFee}(
                    data.party,
                    payable(address(0)),
                    0
                );
            } else {
                payable(recipient.recipient).transfer(recipientFee);
            }
        }

        // Distribute token fees to recipients
        for (uint256 i = 0; i < data.recipients.length; i++) {
            FeeRecipient memory recipient = data.recipients[i];
            uint256 recipientTokenFee = (tokenAmount *
                recipient.percentageBps) / 1e4;
            if (data.isFirstRecipientDistributor && i == 0) {
                token.transfer(address(TOKEN_DISTRIBUTOR), recipientTokenFee);
                TOKEN_DISTRIBUTOR.createErc20Distribution(
                    IERC20(address(token)),
                    data.party,
                    payable(address(0)),
                    0
                );
            } else {
                token.transfer(recipient.recipient, recipientTokenFee);
            }
        }
    }

    function setPartyDaoFeeBps(uint16 _partyDaoFeeBps) external {
        require(msg.sender == PARTY_DAO, "Only PartyDAO can set fee");
        partyDaoFeeBps = _partyDaoFeeBps;
    }

    function setCollectCooldown(uint256 _collectCooldown) external {
        require(msg.sender == PARTY_DAO, "Only PartyDAO can set cooldown");
        collectCooldown = _collectCooldown;
    }

    function setFeeRecipients(
        uint256 positionTokenId,
        PositionData calldata _positionData
    ) external {
        // TODO: Allow other contract (e.g. ERC20Creator) to set fee recipients also?
        require(
            msg.sender == address(_positionData.party),
            "Only party can set fee recipients"
        );

        // Calculate the total percentage basis points
        uint256 totalPercentageBps = 0;
        for (uint256 i = 0; i < _positionData.recipients.length; i++) {
            totalPercentageBps += _positionData.recipients[i].percentageBps;
        }

        // Ensure the total percentage basis points equal 1e4 (100%)
        require(totalPercentageBps == 1e4, "Total percentageBps must be 100%");

        positionData[positionTokenId] = _positionData;
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        // TODO: Restrict to only Uniswap V3 LPs
        (Party party, PositionData memory _positionData) = abi.decode(
            data,
            (Party, PositionData)
        );

        PositionData storage position = positionData[tokenId];
        position.party = party;
        position.lastCollectTimestamp = _positionData.lastCollectTimestamp;
        position.isFirstRecipientDistributor = _positionData
            .isFirstRecipientDistributor;

        for (uint256 i = 0; i < _positionData.recipients.length; i++) {
            position.recipients.push(_positionData.recipients[i]);
        }

        return this.onERC721Received.selector;
    }
}
