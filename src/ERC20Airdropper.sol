// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {GovernableERC20} from "./GovernableERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Dropper} from "./vendor/Dropper.sol";

contract ERC20Airdropper {
    struct TokenArgs {
        string name;
        string symbol;
        // Token metadata image URI that only gets emitted (not stored on-chain)
        string image;
        // Token metadata description that only gets emitted (not stored on-chain)
        string description;
        uint256 totalSupply;
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

    event ERC20Created(
        address indexed token,
        string name,
        string symbol,
        string image,
        string description,
        uint256 totalSupply
    );

    event DropCreated(
        uint256 indexed dropId,
        address indexed token,
        bytes32 merkleRoot,
        uint256 totalTokens,
        uint40 startTimestamp,
        uint40 expirationTimestamp
    );

    Dropper public immutable DROPPER;

    constructor(Dropper _dropper) {
        DROPPER = _dropper;
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
            tokenArgs.totalSupply,
            receiver
        );

        emit ERC20Created(
            address(token),
            tokenArgs.name,
            tokenArgs.symbol,
            tokenArgs.image,
            tokenArgs.description,
            tokenArgs.totalSupply
        );
    }
}
