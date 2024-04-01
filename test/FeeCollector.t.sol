// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import {MockUniswapV3Deployer, MockUniswapNonfungiblePositionManager} from "./mock/MockUniswapV3Deployer.t.sol";
import {MockTokenDistributor} from "./mock/MockTokenDistributor.t.sol";
import {MockParty} from "./mock/MockParty.t.sol";
import {ERC20CreatorV3, IERC20} from "src/ERC20CreatorV3.sol";
import {FeeCollector, FeeRecipient, PositionData, IWETH} from "../src/FeeCollector.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {ITokenDistributor} from "party-protocol/contracts/distribution/ITokenDistributor.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
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
        PositionData memory positionParams
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
                address(party),
                "My Test Token",
                "MTT",
                tokenConfig,
                address(this),
                address(feeCollector),
                10_000,
                positionParams
            )
        );
        tokenId = MockUniswapNonfungiblePositionManager(
            address(positionManager)
        ).lastTokenId();
    }

    function testCollectAndDistributeFees() public {
        FeeRecipient[] memory recipients = new FeeRecipient[](2);
        recipients[0] = FeeRecipient(
            payable(vm.createWallet("Recipient1").addr),
            0.5e4 // 50%
        );
        recipients[1] = FeeRecipient(
            payable(vm.createWallet("Recipient2").addr),
            0.5e4 // 50%
        );

        PositionData memory positionParams = PositionData({
            party: party,
            recipients: recipients
        });

        (IERC20 token, uint256 tokenId) = _setUpTokenAndPool(positionParams);

        Party storedParty = feeCollector.getPositionData(tokenId);
        FeeRecipient[] memory storedRecipients = feeCollector.getFeeRecipients(
            tokenId
        );

        assertEq(address(storedParty), address(party));
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

        assertEq(ethAmount, 1e18);
        assertEq(tokenAmount, 1000e18);

        // Check PartyDAO fee deduction
        uint256 expectedPartyDaoFee = (ethAmount *
            feeCollector.partyDaoFeeBps()) / 1e4;
        uint256 expectedRemainingEth = ethAmount - expectedPartyDaoFee;
        assertEq(
            address(feeCollector.PARTY_DAO()).balance,
            expectedPartyDaoFee
        );

        // Check distribution to recipients
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(
                address(recipients[i].recipient).balance,
                (expectedRemainingEth * recipients[i].percentageBps) / 1e4
            );
            assertEq(
                token.balanceOf(recipients[i].recipient),
                (tokenAmount * recipients[i].percentageBps) / 1e4
            );
        }
    }

    function testSetPartyDaoFeeBps() public {
        uint16 newFeeBps = 500; // 5%
        vm.prank(address(feeCollector.PARTY_DAO()));
        feeCollector.setPartyDaoFeeBps(newFeeBps);
        assertEq(feeCollector.partyDaoFeeBps(), newFeeBps);
    }

    function testSetPartyDaoFeeBpsRevertNotPartyDAO() public {
        uint16 newFeeBps = 500; // 5%
        vm.expectRevert(
            abi.encodeWithSelector(FeeCollector.OnlyPartyDAO.selector)
        );
        feeCollector.setPartyDaoFeeBps(newFeeBps);
    }
}
