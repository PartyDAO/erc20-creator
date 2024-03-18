// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/ERC20Creator.sol";
import "./utils/TestUtils.sol";

contract TestContract is Test, TestUtils {
    // addresses
    address feeRecipient;
    address partyAddress;
    address mockRouter;
    address recipientAddress;

    // LP
    uint256 feeBasisPoints;

    // Token Details
    string name = "Leet H4x0rs";
    string symbol = "1337";
    uint256 totalSupply = 100 ether;
    uint256 numTokensForRecipient = 10 ether;
    uint256 numTokensForDistribution = 10 ether;

    function setUp() public {
        feeRecipient = _randomAddress(); // TODO: make Address
        vm.label(feeRecipient, "feeRecipient");

        partyAddress = _randomAddress(); // TODO: make Address
        vm.label(partyAddress, "partyAddress");

        mockRouter = _randomAddress(); // TODO: make Address
        vm.label(mockRouter, "mockRouter");

        recipientAddress = _randomAddress(); // TODO: make Address
        vm.label(recipientAddress, "recipientAddress");

        feeBasisPoints = 100;
    }

    function test_demo() public {
        ERC20Creator creator = _deployERC20Creator();

        ERC20 newErc20 = creator.createToken(
            partyAddress,
            name,
            symbol,
            ERC20Creator.TokenConfiguration({
                totalSupply: totalSupply,
                numTokensForDistribution: numTokensForDistribution,
                numTokensForRecipient: numTokensForRecipient,
                numTokensForLP: 80 ether
            }),
            recipientAddress
        );

        emit log_named_address("erc20", address(newErc20));

        // ensure token is created
        assertTrue(_isContract(address(newErc20)), "not contract");
        assertEq(
            keccak256(abi.encode(name)),
            keccak256(abi.encode(newErc20.name())),
            "name mismatch"
        );

        // ensure totalSupply is what we expect
        assertEq(totalSupply, newErc20.totalSupply(), "totalSupply mismatch");

        // ensure recipient has gotten amount we expect
        assertEq(
            numTokensForRecipient,
            newErc20.balanceOf(recipientAddress),
            "recipient balance mismatch"
        );

        // ensure the party has gotten the amount we expect
        assertEq(
            numTokensForDistribution,
            newErc20.balanceOf(partyAddress),
            "party balance mismatch"
        );
    }

    // should fail with incorrect config

    //

    function _deployERC20Creator() internal returns (ERC20Creator) {
        return new ERC20Creator(mockRouter, feeRecipient, feeBasisPoints);
    }

    // later: LP
}
