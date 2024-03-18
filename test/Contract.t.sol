// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/ERC20Creator.sol";

contract TestContract is Test {
    address feeRecipient;
    uint256 feeBasisPoints;

    function setup() public {
        feeRecipient = address(1337); // TODO: make Address
        vm.label(feeRecipient, "feeRecipient");
        feeBasisPoints = 100;
    }

    function test_demo() public {
        ERC20Creator creator = new ERC20Creator(
            address(99),
            feeRecipient,
            feeBasisPoints
        );

        address partyAddress = address(55);

        IERC20 newErc20 = creator.createToken(
            partyAddress,
            "Leet H4x0rs",
            "1337",
            ERC20Creator.TokenConfiguration({
                totalSupply: 100 ether,
                numTokensForDistribution: 10 ether,
                numTokensForRecipient: 10 ether,
                numTokensForLP: 80 ether
            }),
            address(3)
        );

        assert(true);

        // ensure token is created
        // ensure totalSupply is what we expect
        // ensure recipient has gotten amount we expect
    }

    // later: LP
}
