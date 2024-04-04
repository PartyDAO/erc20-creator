// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../src/ERC20CreatorV3.sol";
import {ERC20Votes} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {MockParty} from "./mock/MockParty.t.sol";
import {FeeCollector} from "src/FeeCollector.sol";
import {IWETH} from "v2-periphery/interfaces/IWETH.sol";

contract ERC20CreatorV3ForkTest is Test {
    ERC20CreatorV3 public creator;

    ITokenDistributor public tokenDistributor;
    address public weth;

    Party public party;
    uint16 public feeBasisPoints;
    PositionData public positionParams;
    FeeCollector public feeCollector;
    INonfungiblePositionManager public positionManager;
    address payable public partyDao;

    function setUp() public {
        tokenDistributor = ITokenDistributor(
            0xf0560F963538017CAA5081D96f839FE5D265acCB
        );

        positionManager = INonfungiblePositionManager(
            0x1238536071E1c677A632429e3655c799b22cDA52
        );
        weth = positionManager.WETH9();
        Vm.Wallet memory partyWallet = vm.createWallet("PartyDao");
        partyDao = payable(partyWallet.addr);

        feeBasisPoints = 100;

        party = Party(payable(address(new MockParty())));
        vm.label(address(party), "Party");

        feeCollector = new FeeCollector(
            positionManager,
            partyDao,
            100,
            IWETH(address(weth))
        );
    }

    function testForked_createToken_1PercentFee() external {
        forked_createToken_xPercentFee(10_000); // 1% fee
    }

    function testForked_createToken_03PercentFee() external {
        forked_createToken_xPercentFee(3_000); // 0.3% fee
    }

    function testForked_createToken_005PercentFee() external {
        forked_createToken_xPercentFee(500); // 0.05% fee
    }

    function forked_createToken_xPercentFee(uint16 poolFee) internal {
        creator = new ERC20CreatorV3(
            tokenDistributor,
            positionManager,
            IUniswapV3Factory(0x0227628f3F023bb0B980b67D528571c95c6DaC1c),
            address(feeCollector),
            positionManager.WETH9(),
            partyDao,
            feeBasisPoints,
            poolFee
        );

        address receiver = vm.createWallet("Receiver").addr;
        uint256 eth = 10 ether;
        uint256 fee = (eth * feeBasisPoints) / 1e4;

        uint256 totalSupply = 100 ether;
        uint256 numTokensForDistribution = 10 ether;
        uint256 numTokensForRecipient = 10 ether;
        uint256 numTokensForLP = 80 ether;

        vm.deal(address(party), 10 ether);
        vm.prank(address(party));
        ERC20Votes token = ERC20Votes(
            address(
                creator.createToken{value: eth}(
                    address(party),
                    "Leet H4x0rs",
                    "1337",
                    ERC20CreatorV3.TokenDistributionConfiguration({
                        totalSupply: totalSupply,
                        numTokensForDistribution: numTokensForDistribution,
                        numTokensForRecipient: numTokensForRecipient,
                        numTokensForLP: numTokensForLP
                    }),
                    receiver
                )
            )
        );
        address pool = creator.getPool(address(token));

        assertApproxEqRel(
            token.balanceOf(pool),
            numTokensForLP,
            0.001 ether /* 0.1% tolerance */
        );
        assertApproxEqRel(
            IERC20(weth).balanceOf(pool),
            eth - fee,
            0.001 ether /* 0.1% tolerance */
        );
        assertEq(partyDao.balance, fee);
        assertEq(token.balanceOf(receiver), numTokensForRecipient);
        assertEq(
            token.balanceOf(address(tokenDistributor)),
            numTokensForDistribution
        );
        assertEq(token.totalSupply(), totalSupply);

        Vm.Wallet memory wallet = vm.createWallet("Tester");
        vm.prank(wallet.addr);
        token.delegate(wallet.addr);

        vm.prank(receiver);
        token.transfer(wallet.addr, 100);

        assertEq(token.balanceOf(wallet.addr), 100);
        assertEq(token.balanceOf(receiver), numTokensForRecipient - 100);

        assertEq(token.getVotes(wallet.addr), 100);
        assertEq(token.getVotes(receiver), 0);
    }
}
