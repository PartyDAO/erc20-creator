// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import { GovernableERC20 } from "./GovernableERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Dropper } from "dropper-util/src/Dropper.sol";

contract ERC20Airdropper {
    struct TokenArgs {
        string name;
        string symbol;
        // Token metadata image URI that only gets emitted (not stored on-chain)
        string image;
        // Token metadata description that only gets emitted (not stored on-chain)
        string description;
        uint256 totalSupply;
        address owner;
    }

    struct DropArgs {
        bytes32 merkleRoot;
        uint256 totalTokens;
        uint40 startTimestamp;
        uint40 expirationTimestamp;
        address expirationRecipient;
        string merkleTreeURI;
        string dropDescription;
    }

    event DropCreated(
        uint256 indexed dropId,
        address indexed token,
        bytes32 merkleRoot,
        uint256 totalTokens,
        uint40 startTimestamp,
        uint40 expirationTimestamp
    );

    event ERC20Created(
        address indexed token,
        address indexed owner,
        string name,
        string symbol,
        uint256 totalSupply
    );

    Dropper public immutable DROPPER;

    constructor(Dropper dropper) {
        DROPPER = dropper;
    }

    function createTokenAndAirdrop(
        TokenArgs memory tokenArgs,
        DropArgs memory dropArgs
    ) external returns (ERC20 token, uint256 dropId) {
        token = createToken(tokenArgs, address(this));

        token.approve(address(DROPPER), dropArgs.totalTokens);

        dropId = DROPPER.createDrop(
            dropArgs.merkleRoot,
            dropArgs.totalTokens,
            address(token),
            dropArgs.startTimestamp,
            dropArgs.expirationTimestamp,
            dropArgs.expirationRecipient,
            dropArgs.merkleTreeURI,
            dropArgs.dropDescription
        );

        emit DropCreated(
            dropId,
            address(token),
            dropArgs.merkleRoot,
            dropArgs.totalTokens,
            dropArgs.startTimestamp,
            dropArgs.expirationTimestamp
        );

        uint256 remaining = token.balanceOf(address(this));
        if (remaining > 0) {
            token.transfer(msg.sender, remaining);
        }
    }

    function createToken(
        TokenArgs memory tokenArgs,
        address receiver
    ) public returns (ERC20 token) {
        token = new GovernableERC20(
            tokenArgs.name,
            tokenArgs.symbol,
            tokenArgs.image,
            tokenArgs.description,
            tokenArgs.totalSupply,
            receiver,
            tokenArgs.owner
        );

        emit ERC20Created(
            address(token),
            tokenArgs.owner,
            tokenArgs.name,
            tokenArgs.symbol,
            tokenArgs.totalSupply
        );
    }
}