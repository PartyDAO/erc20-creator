// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/GovernableERC20.sol";

contract GovernableERC20Test is Test {
    function _createToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address receiver
    ) internal returns (GovernableERC20) {
        return new GovernableERC20(name, symbol, totalSupply, receiver);
    }

    function _createToken() internal returns (GovernableERC20) {
        return _createToken("Test", "TST", 1_000_000e18, vm.addr(1));
    }

    function test_creation() public {
        string memory name = "Test";
        string memory symbol = "TST";
        uint256 totalSupply = 1_000_000e18;
        address receiver = vm.addr(1);

        GovernableERC20 token = _createToken(
            name,
            symbol,
            totalSupply,
            receiver
        );

        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.totalSupply(), totalSupply);
        assertEq(token.balanceOf(receiver), totalSupply);
    }

    function test_snapshotting() public {
        address receiver = vm.addr(1);

        GovernableERC20 token = _createToken();

        // Transfer some tokens to another address
        address other = vm.addr(2);
        uint256 amount = 100e18;
        vm.prank(receiver);
        token.transfer(other, amount);
        assertEq(token.balanceOf(receiver), 1_000_000e18 - amount);
        assertEq(token.balanceOf(other), amount);
        assertEq(token.getVotes(receiver), 1_000_000e18 - amount);
        assertEq(token.getVotes(other), amount);
    }
}
