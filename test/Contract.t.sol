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
        assertEq(name, newErc20.name(), "name mismatch");

        // ensure totalSupply is what we expect
        // assertEq(totalSupply, newErc20.totalSupply(), "totalSupply mismatch");

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
    // function testFuzz_ShouldSucceed_WhenNumTokensIsCorrect(
    //     uint256 totalSupplyFuzz,
    //     uint256 numTokensForDistributionFuzz,
    //     uint256 numTokensForRecipientFuzz
    // ) public {
    //     vm.assume(
    //         totalSupplyFuzz > 0 && totalSupplyFuzz < 420_000_000_000 ether
    //     );
    //     vm.assume(numTokensForDistributionFuzz < totalSupplyFuzz);
    //     vm.assume(numTokensForRecipientFuzz <= numTokensForDistributionFuzz);

    //     uint256 numTokensForLpDerived = totalSupplyFuzz -
    //         numTokensForDistributionFuzz -
    //         numTokensForRecipientFuzz;

    //     ERC20Creator creator = _deployERC20Creator();

    //     assertEq(
    //         totalSupplyFuzz,
    //         numTokensForDistributionFuzz +
    //             numTokensForRecipientFuzz +
    //             numTokensForLpDerived,
    //         "token supply config"
    //     );
    //     ERC20 newErc20 = creator.createToken(
    //         partyAddress,
    //         name,
    //         symbol,
    //         ERC20Creator.TokenConfiguration({
    //             totalSupply: totalSupplyFuzz,
    //             numTokensForDistribution: numTokensForDistributionFuzz,
    //             numTokensForRecipient: numTokensForRecipientFuzz,
    //             numTokensForLP: numTokensForLpDerived
    //         }),
    //         recipientAddress
    //     );
    // }

    // should fail when distributions exceed supply
    function test_shouldFail_WhenDistributionsExceedTotalSupply() public {
        ERC20Creator creator = _deployERC20Creator();

        uint256 supply = 420_000_000 ether;
        uint256 distributionTokens = supply / 3;
        uint256 recipientTokens = supply / 3;
        uint256 lpTokens = supply / 3;
        assertEq(
            supply,
            distributionTokens + recipientTokens + lpTokens,
            "token supply config"
        );

        vm.expectRevert(bytes("Invalid token distribution"));
        ERC20 newErc20 = creator.createToken(
            partyAddress,
            name,
            symbol,
            ERC20Creator.TokenConfiguration({
                totalSupply: supply,
                numTokensForDistribution: distributionTokens,
                numTokensForRecipient: recipientTokens + 1,
                numTokensForLP: lpTokens
            }),
            recipientAddress
        );

        vm.expectRevert(bytes("Invalid token distribution"));
        newErc20 = creator.createToken(
            partyAddress,
            name,
            symbol,
            ERC20Creator.TokenConfiguration({
                totalSupply: supply,
                numTokensForDistribution: distributionTokens + 1,
                numTokensForRecipient: recipientTokens,
                numTokensForLP: lpTokens
            }),
            recipientAddress
        );

        vm.expectRevert(bytes("Invalid token distribution"));
        newErc20 = creator.createToken(
            partyAddress,
            name,
            symbol,
            ERC20Creator.TokenConfiguration({
                totalSupply: supply,
                numTokensForDistribution: distributionTokens,
                numTokensForRecipient: recipientTokens,
                numTokensForLP: lpTokens + 1
            }),
            recipientAddress
        );

        vm.expectRevert(bytes("Invalid token distribution"));
        newErc20 = creator.createToken(
            partyAddress,
            name,
            symbol,
            ERC20Creator.TokenConfiguration({
                totalSupply: supply - 1,
                numTokensForDistribution: distributionTokens,
                numTokensForRecipient: recipientTokens,
                numTokensForLP: lpTokens
            }),
            recipientAddress
        );
    }

    function _deployERC20Creator() internal returns (ERC20Creator) {
        return new ERC20Creator(mockRouter, feeRecipient, feeBasisPoints);
    }

    // later: LP
}
