// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/GovernableERC20.sol";

contract GovernableERC20Test is Test {
    event MetadataSet(string image, string description);

    function _createToken(
        string memory name,
        string memory symbol,
        string memory image,
        string memory description,
        uint256 totalSupply,
        address receiver,
        address owner
    ) internal returns (GovernableERC20) {
        return new GovernableERC20(name, symbol, image, description, totalSupply, receiver, owner);
    }

    function _createToken() internal returns (GovernableERC20) {
        return
            _createToken(
                "Test",
                "TST",
                "ipfs://exampleImage",
                "description",
                1_000_000e18,
                vm.addr(1),
                vm.addr(2)
            );
    }

    function test_creation() public {
        string memory name = "Test";
        string memory symbol = "TST";
        string memory image = "ipfs://exampleImage";
        string memory description = "description";
        uint256 totalSupply = 1_000_000e18;
        address receiver = vm.addr(1);
        address owner = vm.addr(2);

        vm.expectEmit(true, true, true, true);
        emit MetadataSet(image, description);

        GovernableERC20 token = _createToken(
            name,
            symbol,
            image,
            description,
            totalSupply,
            receiver,
            owner
        );

        vm.prank(receiver);
        token.delegate(receiver);

        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.totalSupply(), totalSupply);
        assertEq(token.balanceOf(receiver), totalSupply);
        assertEq(token.getVotes(receiver), totalSupply);
        assertEq(token.owner(), owner);
    }

    function test_snapshotting() public {
        address receiver = vm.addr(1);

        GovernableERC20 token = _createToken();

        vm.prank(receiver);
        token.delegate(receiver);

        // Transfer some tokens to another address
        address other = vm.addr(2);
        uint256 amount = 100e18;

        vm.prank(receiver);
        token.transfer(other, amount);
        vm.prank(other);
        token.delegate(other);

        assertEq(token.balanceOf(receiver), 1_000_000e18 - amount);
        assertEq(token.balanceOf(other), amount);
        assertEq(token.getVotes(receiver), 1_000_000e18 - amount);
        assertEq(token.getVotes(other), amount);
    }

    function test_updateImageAndDescription() public {
        GovernableERC20 token = _createToken();
        address owner = vm.addr(2);
        string memory newImage = "ipfs://newImage";
        string memory newDescription = "New Description";

        vm.expectEmit(true, true, true, true);
        emit MetadataSet(newImage, newDescription);

        vm.prank(owner);
        token.setMetadata(newImage, newDescription);
    }
}
