// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../src/ERC20Creator.sol";

contract MockParty {
    struct GovernanceValues {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
        uint96 totalVotingPower;
    }

    function getGovernanceValues()
        external
        pure
        returns (GovernanceValues memory)
    {
        return
            GovernanceValues({
                voteDuration: 1 days,
                executionDelay: 1 days,
                passThresholdBps: 5000,
                totalVotingPower: 1e18
            });
    }

    function tokenCount() external pure returns (uint256) {
        return 100;
    }
}

contract ERC20CreatorTest is Test {
    ERC20Creator creator;

    ITokenDistributor public tokenDistributor;
    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Factory public uniswapV2Factory;
    address public weth;

    Party public party;
    address feeRecipient;
    uint16 feeBasisPoints;

    function setUp() public {
        tokenDistributor = ITokenDistributor(
            0xf0560F963538017CAA5081D96f839FE5D265acCB
        );
        uniswapV2Router = IUniswapV2Router02(
            0x86dcd3293C53Cf8EFd7303B57beb2a3F671dDE98
        );
        uniswapV2Factory = IUniswapV2Factory(uniswapV2Router.factory());
        weth = uniswapV2Router.WETH();

        feeRecipient = vm.addr(1);
        vm.deal(feeRecipient, 0);
        vm.label(feeRecipient, "feeRecipient");
        feeBasisPoints = 100;

        party = Party(payable(address(new MockParty())));
        vm.label(address(party), "Party");

        creator = new ERC20Creator(
            tokenDistributor,
            uniswapV2Router,
            uniswapV2Factory,
            weth,
            feeRecipient,
            feeBasisPoints
        );
    }

    function test_createToken() public {
        address receiver = vm.addr(2);
        uint256 eth = 10 ether;
        uint256 fee = (eth * feeBasisPoints) / 1e4;

        uint256 totalSupply = 100 ether;
        uint256 numTokensForDistribution = 10 ether;
        uint256 numTokensForRecipient = 10 ether;
        uint256 numTokensForLP = 80 ether;

        ERC20 token = creator.createToken{value: eth}(
            address(party),
            "Leet H4x0rs",
            "1337",
            ERC20Creator.TokenConfiguration({
                totalSupply: totalSupply,
                numTokensForDistribution: numTokensForDistribution,
                numTokensForRecipient: numTokensForRecipient,
                numTokensForLP: numTokensForLP
            }),
            receiver
        );
        address pair = creator.getPair(address(token));

        assertEq(pair, uniswapV2Factory.getPair(address(token), weth));
        assertEq(token.balanceOf(pair), numTokensForLP);
        assertEq(ERC20(weth).balanceOf(pair), eth - fee);
        assertEq(feeRecipient.balance, fee);
        assertEq(token.balanceOf(receiver), numTokensForRecipient);
        assertEq(
            token.balanceOf(address(tokenDistributor)),
            numTokensForDistribution
        );
        assertEq(token.totalSupply(), totalSupply);
    }
}
