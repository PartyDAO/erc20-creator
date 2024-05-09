// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/ERC20Airdropper.sol";

contract ERC20AirdropperTest is Test {
    event ERC20Created(
        string name,
        string symbol,
        string image,
        string description,
        uint256 totalSupply,
        address receiver,
        address owner
    );
    event DropCreated(
        uint256 indexed dropId,
        address indexed token,
        bytes32 merkleRoot,
        uint256 totalTokens,
        uint40 startTimestamp,
        uint40 expirationTimestamp
    );

    ERC20Airdropper airdropper;
    Dropper dropper;

    function setUp() public {
        dropper = new Dropper();
        airdropper = new ERC20Airdropper(dropper);
    }

    function testCreateTokenAndAirdrop() public {
        ERC20Airdropper.TokenArgs memory tokenArgs = ERC20Airdropper.TokenArgs({
            name: "Test Token",
            symbol: "TTT",
            image: "ipfs://exampleImage",
            description: "A test token",
            totalSupply: 1000e18,
            owner: vm.addr(2)
        });

        bytes32 merkleRoot = keccak256(abi.encode(vm.addr(1), 100e18));
        ERC20Airdropper.DropArgs memory dropArgs = ERC20Airdropper.DropArgs({
            merkleRoot: merkleRoot,
            totalTokens: 600e18,
            startTimestamp: uint40(block.timestamp),
            expirationTimestamp: uint40(block.timestamp + 1 days),
            expirationRecipient: address(this),
            merkleTreeURI: "ipfs://merkle-tree",
            dropDescription: "Test Airdrop"
        });

        vm.expectEmit(true, true, true, true);
        emit ERC20Created(
            tokenArgs.name,
            tokenArgs.symbol,
            tokenArgs.image,
            tokenArgs.description,
            tokenArgs.totalSupply,
            address(airdropper),
            tokenArgs.owner
        );
        address expectedToken = vm.computeCreateAddress(address(airdropper), 1);
        vm.expectEmit(true, true, true, true);
        emit DropCreated(
            1,
            expectedToken,
            merkleRoot,
            dropArgs.totalTokens,
            dropArgs.startTimestamp,
            dropArgs.expirationTimestamp
        );

        (ERC20 token, uint256 dropId) = airdropper.createTokenAndAirdrop(tokenArgs, dropArgs);

        assertEq(token.name(), tokenArgs.name);
        assertEq(token.symbol(), tokenArgs.symbol);
        assertEq(token.totalSupply(), tokenArgs.totalSupply);

        (
            bytes32 merkleRoot_,
            uint256 totalTokens,
            uint256 claimedTokens,
            address tokenAddress,
            uint40 startTimestamp,
            uint40 expirationTimestamp,
            address expirationRecipient
        ) = dropper.drops(dropId);

        assertEq(dropId, 1);
        assertEq(merkleRoot_, dropArgs.merkleRoot);
        assertEq(totalTokens, dropArgs.totalTokens);
        assertEq(claimedTokens, 0);
        assertEq(tokenAddress, address(token));
        assertEq(startTimestamp, dropArgs.startTimestamp);
        assertEq(expirationTimestamp, dropArgs.expirationTimestamp);
        assertEq(expirationRecipient, dropArgs.expirationRecipient);

        assertEq(token.balanceOf(address(dropper)), dropArgs.totalTokens);
        assertEq(token.balanceOf(address(this)), tokenArgs.totalSupply - dropArgs.totalTokens);
    }

    function testCreateTokenAndAirdrop_noRemainingBalance() public {
        ERC20Airdropper.TokenArgs memory tokenArgs = ERC20Airdropper.TokenArgs({
            name: "Test Token",
            symbol: "TTT",
            image: "ipfs://token-image",
            description: "A test token",
            totalSupply: 1000e18,
            owner: vm.addr(2)
        });

        bytes32 merkleRoot = keccak256(abi.encode(vm.addr(1), 100e18));
        ERC20Airdropper.DropArgs memory dropArgs = ERC20Airdropper.DropArgs({
            merkleRoot: merkleRoot,
            totalTokens: tokenArgs.totalSupply,
            startTimestamp: uint40(block.timestamp),
            expirationTimestamp: uint40(block.timestamp + 1 days),
            expirationRecipient: address(this),
            merkleTreeURI: "ipfs://merkle-tree",
            dropDescription: "Test Airdrop"
        });

        (ERC20 token, ) = airdropper.createTokenAndAirdrop(tokenArgs, dropArgs);

        assertEq(token.balanceOf(address(dropper)), dropArgs.totalTokens);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testCreateTokenAndAirdrop_totalTokensExceedsTotalSupply() public {
        ERC20Airdropper.TokenArgs memory tokenArgs = ERC20Airdropper.TokenArgs({
            name: "Test Token",
            symbol: "TTT",
            image: "ipfs://token-image",
            description: "A test token",
            totalSupply: 1000e18,
            owner: vm.addr(2)
        });

        bytes32 merkleRoot = keccak256(abi.encode(vm.addr(1), 100e18));
        ERC20Airdropper.DropArgs memory dropArgs = ERC20Airdropper.DropArgs({
            merkleRoot: merkleRoot,
            totalTokens: 1200e18,
            startTimestamp: uint40(block.timestamp),
            expirationTimestamp: uint40(block.timestamp + 1 days),
            expirationRecipient: address(this),
            merkleTreeURI: "ipfs://merkle-tree",
            dropDescription: "Test Airdrop"
        });

        vm.expectRevert();
        airdropper.createTokenAndAirdrop(tokenArgs, dropArgs);
    }

    function testCreateTokenOnly() public {
        ERC20Airdropper.TokenArgs memory tokenArgs = ERC20Airdropper.TokenArgs({
            name: "Test Token",
            symbol: "TTT",
            image: "ipfs://token-image",
            description: "A test token without airdrop",
            totalSupply: 1000e18,
            owner: vm.addr(2)
        });

        vm.expectEmit(true, true, true, true);
        emit ERC20Created(
            tokenArgs.name,
            tokenArgs.symbol,
            tokenArgs.image,
            tokenArgs.description,
            tokenArgs.totalSupply,
            address(this),
            tokenArgs.owner
        );

        ERC20 token = airdropper.createToken(tokenArgs, address(this));

        assertEq(token.name(), tokenArgs.name);
        assertEq(token.symbol(), tokenArgs.symbol);
        assertEq(token.totalSupply(), tokenArgs.totalSupply);
        assertEq(token.balanceOf(address(this)), tokenArgs.totalSupply);
    }
}
