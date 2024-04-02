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
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {Party} from "party-protocol/contracts/party/Party.sol";

// MUST run with --fork $SEPOLIA_RPC_URL --evm-version shanghai

contract FeeCollectorForkedTest is Test {
    ERC20CreatorV3 internal creator;
    ITokenDistributor public distributor;
    Party public party;
    address payable public partyDao;
    FeeCollector public feeCollector;
    ISwapRouter public swapRouter;
    INonfungiblePositionManager public positionManager;
    IWETH public weth;

    function setUp() public {
        positionManager = INonfungiblePositionManager(
            0x1238536071E1c677A632429e3655c799b22cDA52
        );
        weth = IWETH(address(positionManager.WETH9()));
        distributor = ITokenDistributor(
            0xf0560F963538017CAA5081D96f839FE5D265acCB
        );
        party = Party(payable(address(new MockParty())));
        partyDao = payable(vm.createWallet("PartyDAO").addr);
        feeCollector = new FeeCollector(positionManager, partyDao, 100, weth);
        swapRouter = ISwapRouter(0x1CF7C7BaE363f46ec16C4F4B095800D5bD0CB382);
        creator = new ERC20CreatorV3(
            distributor,
            positionManager,
            IUniswapV3Factory(0x0227628f3F023bb0B980b67D528571c95c6DaC1c),
            address(weth),
            address(this),
            100 // 1%
        );
    }

    function _setUpTokenAndPool(
        PositionData memory positionParams
    ) internal returns (IERC20 token, uint256 tokenId) {
        ERC20CreatorV3.TokenDistributionConfiguration
            memory tokenConfig = ERC20CreatorV3.TokenDistributionConfiguration({
                totalSupply: 100 ether,
                numTokensForDistribution: 10 ether,
                numTokensForRecipient: 10 ether,
                numTokensForLP: 80 ether
            });

        vm.deal(address(party), 10e18);
        vm.prank(address(party));
        vm.recordLogs();
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
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(positionManager)) {
                continue;
            }
            if (
                logs[i].topics[0] !=
                keccak256("IncreaseLiquidity(uint256,uint128,uint256,uint256)")
            ) {
                continue;
            }
            tokenId = uint256(logs[i].topics[1]);
        }
    }

    function testForkedCollectAndDistributeFees() public {
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

        deal(address(weth), address(this), type(uint128).max);
        IERC20(address(weth)).approve(address(swapRouter), type(uint128).max);
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(token),
                fee: 10_000,
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Collect and distribute fees
        (uint256 ethAmount, uint256 tokenAmount) = feeCollector
            .collectAndDistributeFees(tokenId);
    }
}
