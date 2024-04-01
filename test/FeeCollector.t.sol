// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import {MockUniswapV3Deployer, MockUniswapNonfungiblePositionManager} from "./mock/MockUniswapV3Deployer.t.sol";
import {MockTokenDistributor} from "./mock/MockTokenDistributor.t.sol";
import {MockParty} from "./mock/MockParty.t.sol";
import {ERC20CreatorV3, IERC20} from "src/ERC20CreatorV3.sol";
import {FeeCollector, FeeRecipient, PositionData, IWETH} from "../src/FeeCollector.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {ITokenDistributor} from "party-protocol/contracts/distribution/ITokenDistributor.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {Party} from "party-protocol/contracts/party/Party.sol";

contract FeeCollectorTest is Test, MockUniswapV3Deployer {
    ERC20CreatorV3 internal creator;
    UniswapV3Deployment public uniswap;
    ITokenDistributor public distributor;
    Party public party;
    address payable public partyDao;
    FeeCollector public feeCollector;
    INonfungiblePositionManager public positionManager;

    function setUp() public {
        uniswap = _deployUniswapV3();
        positionManager = INonfungiblePositionManager(uniswap.POSITION_MANAGER);
        distributor = ITokenDistributor(address(new MockTokenDistributor()));
        party = Party(payable(address(new MockParty())));
        partyDao = payable(vm.createWallet("PartyDAO").addr);
        feeCollector = new FeeCollector(
            positionManager,
            distributor,
            partyDao,
            IWETH(uniswap.WETH)
        );
        creator = new ERC20CreatorV3(
            distributor,
            positionManager,
            IUniswapV3Factory(uniswap.FACTORY),
            uniswap.WETH,
            address(this),
            100 // 1%
        );
    }

    function _setUpTokenAndPool(
        PositionData memory positionData
    ) internal returns (IERC20 token, uint256 tokenId) {
        ERC20CreatorV3.TokenDistributionConfiguration
            memory tokenConfig = ERC20CreatorV3.TokenDistributionConfiguration({
                totalSupply: 1000000,
                numTokensForDistribution: 500000,
                numTokensForRecipient: 250000,
                numTokensForLP: 250000
            });

        vm.deal(address(party), 10e18);
        vm.prank(address(party));
        token = IERC20(
            creator.createToken{value: 10e18}(
                "My Test Token",
                "MTT",
                tokenConfig,
                address(this),
                address(feeCollector),
                10_000,
                positionData
            )
        );
        tokenId = MockUniswapNonfungiblePositionManager(
            address(positionManager)
        ).lastTokenId();
    }

    function testCollectAndDistributeFees() public {
        FeeRecipient[] memory recipients = new FeeRecipient[](2);
        recipients[0] = FeeRecipient(vm.addr(1), 0.5e4); // 50%
        recipients[1] = FeeRecipient(vm.addr(2), 0.5e4); // 50%

        PositionData memory positionData = PositionData({
            party: party,
            lastCollectTimestamp: uint40(block.timestamp - 8 days),
            isFirstRecipientDistributor: true,
            recipients: recipients
        });

        (IERC20 token, uint256 tokenId) = _setUpTokenAndPool(positionData);

        (
            Party storedParty,
            uint40 storedLastCollectTimestamp,
            bool storedIsFirstRecipientDistributor
        ) = feeCollector.getPositionData(tokenId);
        FeeRecipient[] memory storedRecipients = feeCollector.getFeeRecipients(
            tokenId
        );

        assertEq(address(storedParty), address(party));
        assertEq(storedLastCollectTimestamp, positionData.lastCollectTimestamp);
        assertEq(
            storedIsFirstRecipientDistributor,
            positionData.isFirstRecipientDistributor
        );
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(storedRecipients[i].recipient, recipients[i].recipient);
            assertEq(
                storedRecipients[i].percentageBps,
                recipients[i].percentageBps
            );
        }

        // Collect and distribute fees
        (uint256 ethAmount, uint256 tokenAmount) = feeCollector
            .collectAndDistributeFees(tokenId);

        // TODO: Write assertions
    }
}
