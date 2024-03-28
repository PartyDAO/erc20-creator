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

    struct FeeRecipientsData {
        FeeRecipient[] recipients;
        bool isFirstRecipientDistributor;
    }

    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;
    address payable public immutable PARTY_DAO;
    IWETH public immutable WETH;

    ITokenDistributor public tokenDistributor;
    uint16 public partyDaoFeeBps;
    uint256 public collectCooldown = 7 days;

    mapping(Party => FeeRecipientsData) public feeRecipientData;
    mapping(INonfungiblePositionManager => Party) public positionToParty;
    mapping(Party => uint256) public lastCollectTimestamp;

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
        Party party = positionToParty[position];
        require(
            block.timestamp >= lastCollectTimestamp[party] + collectCooldown,
            "Cooldown not over"
        );
        lastCollectTimestamp[party] = block.timestamp;

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

        FeeRecipientsData memory recipientsData = feeRecipientData[party];

        // Distribute ETH fees to recipients
        uint256 remainingEthFees = ethAmount - partyDaoFee;
        for (uint256 i = 0; i < recipientsData.recipients.length; i++) {
            FeeRecipient memory recipient = recipientsData.recipients[i];
            uint256 recipientFee = (remainingEthFees *
                recipient.percentageBps) / 1e4;
            if (recipientsData.isFirstRecipientDistributor && i == 0) {
                TOKEN_DISTRIBUTOR.createNativeDistribution{value: recipientFee}(
                    Party(payable(recipient.recipient)),
                    payable(address(0)),
                    0
                );
            } else {
                payable(recipient.recipient).transfer(recipientFee);
            }
        }

        // Distribute token fees to recipients
        for (uint256 i = 0; i < recipientsData.recipients.length; i++) {
            FeeRecipient memory recipient = recipientsData.recipients[i];
            uint256 recipientTokenFee = (tokenAmount *
                recipient.percentageBps) / 1e4;
            if (recipientsData.isFirstRecipientDistributor && i == 0) {
                token.transfer(address(TOKEN_DISTRIBUTOR), recipientTokenFee);
                TOKEN_DISTRIBUTOR.createErc20Distribution(
                    IERC20(address(token)),
                    Party(payable(recipient.recipient)),
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
        Party party,
        FeeRecipientsData calldata _feeRecipientData
    ) external {
        // TODO: Allow other contract (e.g. ERC20Creator) to set fee recipients also?
        require(msg.sender == address(party), "Unauthorized");

        // Calculate the total percentage basis points
        uint256 totalPercentageBps = 0;
        for (uint256 i = 0; i < _feeRecipientData.recipients.length; i++) {
            totalPercentageBps += _feeRecipientData.recipients[i].percentageBps;
        }

        // Ensure the total percentage basis points equal 1e4 (100%)
        require(totalPercentageBps == 1e4, "Total percentageBps must be 100%");

        feeRecipientData[party] = _feeRecipientData;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata data
    ) external returns (bytes4) {
        // TODO: Restrict to only Uniswap V3 LPs
        Party party = abi.decode(data, (Party));
        positionToParty[INonfungiblePositionManager(msg.sender)] = party;
        return this.onERC721Received.selector;
    }
}
