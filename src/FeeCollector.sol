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

struct TokenFeeInfo {
    uint16 partyDaoFeeBps;
    FeeRecipient[] recipients;
}

contract FeeCollector is IERC721Receiver {
    /// @notice The NonfungiblePositionManager contract from Uniswap V3.
    INonfungiblePositionManager public immutable POSITION_MANAGER;
    /// @notice The PartyDAO's multisig address.
    address payable public immutable PARTY_DAO;
    /// @notice The WETH contract used by Uniswap V3.
    IWETH public immutable WETH;

    /// @notice The global fee percentage (in basis points) that goes to the PartyDAO.
    uint16 public globalPartyDaoFeeBps;
    mapping(uint256 => TokenFeeInfo) private _tokenIdToFeeInfo;

    error InvalidLPPosition();
    error OnlyPartyDAO();
    error OnlyV3PositionManager();
    error InvalidPercentageBps();
    error ArityMismatch();

    event FeesCollectedAndDistributed(
        uint256 tokenId,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 partyDaoFee,
        FeeRecipient[] recipients
    );
    event GlobalPartyDaoFeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);

    /**
     * @param _positionManager The NonfungiblePositionManager contract from Uniswap V3.
     * @param _partyDao The PartyDAO's multisig address.
     * @param _weth The WETH contract used by Uniswap V3.
     * @param _partyDaoFeeBps The fee percentage (in basis points) that goes to the PartyDAO.
     */
    constructor(
        INonfungiblePositionManager _positionManager,
        address payable _partyDao,
        uint16 _partyDaoFeeBps,
        IWETH _weth
    ) {
        POSITION_MANAGER = _positionManager;
        PARTY_DAO = _partyDao;
        WETH = _weth;
        globalPartyDaoFeeBps = _partyDaoFeeBps;
    }

    /**
     * @notice Collects and distributes fees for a given token ID.
     * @param tokenId The ID of the token for which to collect and distribute fees.
     * @return ethAmount The amount of ETH collected as fees.
     * @return tokenAmount The amount of tokens collected as fees.
     */
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
        uint256 partyDaoFee = (ethAmount *
            _tokenIdToFeeInfo[tokenId].partyDaoFeeBps) / 1e4;
        PARTY_DAO.call{value: partyDaoFee, gas: 100_000}("");

        FeeRecipient[] memory recipients = _tokenIdToFeeInfo[tokenId]
            .recipients;

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

    /**
     * @notice Updates the global PartyDAO fee in basis points to use for all future token IDs.
     * @param newFeeBps The new fee percentage (in basis points) for the PartyDAO.
     */
    function setGlobalPartyDaoFeeBps(uint16 newFeeBps) external {
        if (msg.sender != PARTY_DAO) revert OnlyPartyDAO();
        if (newFeeBps > 1e4) revert InvalidPercentageBps();
        emit GlobalPartyDaoFeeBpsUpdated(globalPartyDaoFeeBps, newFeeBps);
        globalPartyDaoFeeBps = newFeeBps;
    }

    /**
     * @notice Retrieves the fee recipients for a given token ID.
     * @param tokenId The ID of the token for which to retrieve fee recipients.
     */
    function getFeeRecipients(
        uint256 tokenId
    ) external view returns (FeeRecipient[] memory) {
        return _tokenIdToFeeInfo[tokenId].recipients;
    }

    /**
     * @notice Retrieves the PartyDAO fee in basis points for a given token ID.
     * @param tokenId The ID of the token for which to retrieve the PartyDAO fee.
     */
    function getPartyDaoFeeBps(uint256 tokenId) external view returns (uint16) {
        return _tokenIdToFeeInfo[tokenId].partyDaoFeeBps;
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
        FeeRecipient[] storage recipients = _tokenIdToFeeInfo[tokenId]
            .recipients;

        _tokenIdToFeeInfo[tokenId].partyDaoFeeBps = globalPartyDaoFeeBps;

        uint256 totalPercentageBps;
        for (uint256 i = 0; i < _recipients.length; i++) {
            recipients.push(_recipients[i]);
            totalPercentageBps += _recipients[i].percentageBps;
        }

        if (totalPercentageBps != 1e4) revert InvalidPercentageBps();

        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
