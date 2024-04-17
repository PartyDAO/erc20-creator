// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IERC721Receiver} from "openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IWETH} from "../lib/v2-periphery/contracts/interfaces/IWETH.sol";
import {Party} from "party-protocol/contracts/party/Party.sol";
import {ITokenDistributor, IERC20} from "party-protocol/contracts/distribution/ITokenDistributor.sol";

struct FeeRecipient {
    address recipient;
    uint16 percentageBps;
}

contract FeeCollector is IERC721Receiver {
    INonfungiblePositionManager public immutable POSITION_MANAGER;
    address payable public immutable PARTY_DAO;
    IWETH public immutable WETH;

    uint16 public partyDaoFeeBps;

    mapping(uint256 tokenId => FeeRecipient[] recipients)
        private _feeRecipients;

    error InvalidLPPosition();
    error OnlyPartyDAO();
    error OnlyV3PositionManager();
    error InvalidPercentageBps();

    event FeesCollectedAndDistributed(
        uint256 tokenId,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 partyDaoFee,
        FeeRecipient[] recipients
    );
    event PartyDaoFeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);

    constructor(
        INonfungiblePositionManager _positionManager,
        address payable _partyDao,
        uint16 _partyDaoFeeBps,
        IWETH _weth
    ) {
        POSITION_MANAGER = _positionManager;
        PARTY_DAO = _partyDao;
        WETH = _weth;
        partyDaoFeeBps = _partyDaoFeeBps;
    }

    function collectAndDistributeFees(
        uint256 tokenId
    ) external returns (uint256 ethAmount, uint256 tokenAmount) {
        // Collect fees from the LP position
        ERC20 token;
        {
            INonfungiblePositionManager.CollectParams
                memory params = INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                });

            (uint256 amount0, uint256 amount1) = POSITION_MANAGER.collect(
                params
            );

            (, bytes memory res) = address(POSITION_MANAGER).staticcall(
                abi.encodeWithSelector(
                    POSITION_MANAGER.positions.selector,
                    tokenId
                )
            );
            (, , address token0, address token1) = abi.decode(
                res,
                (uint96, address, address, address)
            );

            if (token0 == address(WETH)) {
                token = ERC20(token1);
                ethAmount = amount0;
                tokenAmount = amount1;
            } else if (token1 == address(WETH)) {
                token = ERC20(token0);
                ethAmount = amount1;
                tokenAmount = amount0;
            } else {
                revert InvalidLPPosition();
            }

            // Convert WETH to ETH
            WETH.withdraw(ethAmount);
        }

        // Take PartyDAO fee on ETH from the LP position
        uint256 partyDaoFee = (ethAmount * partyDaoFeeBps) / 1e4;
        PARTY_DAO.call{value: partyDaoFee, gas: 100_000}("");

        FeeRecipient[] memory recipients = _feeRecipients[tokenId];

        // Distribute the ETH and tokens to recipients
        uint256 remainingEthFees = ethAmount - partyDaoFee;
        for (uint256 i = 0; i < recipients.length; i++) {
            FeeRecipient memory recipient = recipients[i];
            uint256 recipientEthFee = (remainingEthFees *
                recipient.percentageBps) / 1e4;
            uint256 recipientTokenFee = (tokenAmount *
                recipient.percentageBps) / 1e4;

            if (recipientTokenFee > 0) {
                token.transfer(recipient.recipient, recipientTokenFee);
            }

            if (recipientEthFee > 0) {
                payable(recipient.recipient).call{
                    value: recipientEthFee,
                    gas: 100_000
                }("");
            }
        }

        emit FeesCollectedAndDistributed(
            tokenId,
            ethAmount,
            tokenAmount,
            partyDaoFee,
            recipients
        );
    }

    function setPartyDaoFeeBps(uint16 _partyDaoFeeBps) external {
        if (msg.sender != PARTY_DAO) revert OnlyPartyDAO();
        emit PartyDaoFeeBpsUpdated(partyDaoFeeBps, _partyDaoFeeBps);
        partyDaoFeeBps = _partyDaoFeeBps;
    }

    function getFeeRecipients(
        uint256 tokenId
    ) external view returns (FeeRecipient[] memory) {
        return _feeRecipients[tokenId];
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        if (msg.sender != address(POSITION_MANAGER))
            revert OnlyV3PositionManager();

        FeeRecipient[] memory _recipients = abi.decode(data, (FeeRecipient[]));
        FeeRecipient[] storage recipients = _feeRecipients[tokenId];

        uint256 totalPercentageBps;
        for (uint256 i = 0; i < _recipients.length; i++) {
            recipients.push(_recipients[i]);
            totalPercentageBps += _recipients[i].percentageBps;
        }

        if (totalPercentageBps != 1e4) revert InvalidPercentageBps();

        return this.onERC721Received.selector;
    }

    receive() external payable {}

    /**
     * @dev Returns the version of the contract. Decimal versions indicate change in logic. Number change indicates
     * change in ABI.
     */
    function VERSION() external pure returns (string memory) {
        return "1.0.0";
    }
}
