// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import {MockUniswapV3Deployer, MockUniswapNonfungiblePositionManager} from "./mock/MockUniswapV3Deployer.t.sol";
import {MockTokenDistributor} from "./mock/MockTokenDistributor.t.sol";
import {MockParty} from "./mock/MockParty.t.sol";
import {ERC20CreatorV3, IERC20} from "src/ERC20CreatorV3.sol";
import {FeeCollector, FeeRecipient, IWETH} from "../src/FeeCollector.sol";
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
            partyDao,
            100,
            IWETH(uniswap.WETH)
        );
        creator = new ERC20CreatorV3(
            distributor,
            positionManager,
            IUniswapV3Factory(uniswap.FACTORY),
            address(feeCollector),
            uniswap.WETH,
            partyDao,
            100, // 1%
            10_000 // 1%
        );
    }

    function _setUpTokenAndPool()
        internal
        returns (IERC20 token, uint256 tokenId)
    {
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
                address(party),
                "My Test Token",
                "MTT",
                tokenConfig,
                address(this)
            )
        );
        tokenId = MockUniswapNonfungiblePositionManager(
            address(positionManager)
        ).lastTokenId();
    }

    function testCollectAndDistributeFees() public {
        FeeRecipient[] memory recipients = new FeeRecipient[](1);
        recipients[0] = FeeRecipient(payable(address(party)), 1e4);

        (IERC20 token, uint256 tokenId) = _setUpTokenAndPool();

        FeeRecipient[] memory storedRecipients = feeCollector.getFeeRecipients(
            tokenId
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(storedRecipients[i].recipient, recipients[i].recipient);
            assertEq(
                storedRecipients[i].percentageBps,
                recipients[i].percentageBps
            );
        }

        uint256 partyDaoBalanceBefore = partyDao.balance;

        // Collect and distribute fees
        (uint256 ethAmount, uint256 tokenAmount) = feeCollector
            .collectAndDistributeFees(tokenId);

        assertEq(ethAmount, 1e18);
        assertEq(tokenAmount, 1000e18);

        // Check PartyDAO fee deduction
        uint256 expectedPartyDaoFee = (ethAmount *
            feeCollector.partyDaoFeeBps()) / 1e4;
        uint256 expectedRemainingEth = ethAmount - expectedPartyDaoFee;
        assertEq(partyDao.balance - partyDaoBalanceBefore, expectedPartyDaoFee);

        // TODO: Fix assertion
        // assertEq(
        //     address(recipients[i].recipient).balance,
        //     expectedRemainingEth
        // );
        // assertEq(token.balanceOf(recipients[i].recipient), tokenAmount);
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

    function test_createToken_feeRecipientNotParty() external {
        ERC20CreatorV3.TokenDistributionConfiguration
            memory tokenConfig = ERC20CreatorV3.TokenDistributionConfiguration({
                totalSupply: 1000000,
                numTokensForDistribution: 500000,
                numTokensForRecipient: 250000,
                numTokensForLP: 250000
            });

        vm.deal(address(party), 10e18);
        vm.prank(address(party));

        creator.createToken{value: 10e18}(
            address(party),
            address(this),
            "My Test Token",
            "MTT",
            tokenConfig,
            address(this)
        );
        uint256 tokenId = MockUniswapNonfungiblePositionManager(
            address(positionManager)
        ).lastTokenId();

        assertEq(feeCollector.getFeeRecipients(tokenId).length, 1);
        assertEq(
            feeCollector.getFeeRecipients(tokenId)[0].recipient,
            address(this)
        );
        assertEq(feeCollector.getFeeRecipients(tokenId)[0].percentageBps, 1e4);
    }
}
