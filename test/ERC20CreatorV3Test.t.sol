// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";
import {MockUniswapV3Deployer} from "./mock/MockUniswapV3Deployer.t.sol";
import {ERC20CreatorV3, IERC20, FeeRecipient, PositionData} from "src/ERC20CreatorV3.sol";
import {FeeCollector, IWETH, FeeRecipient, PositionData} from "src/FeeCollector.sol";
import {MockUniswapNonfungiblePositionManager} from "test/mock/MockUniswapNonfungiblePositionManager.t.sol";
import {ITokenDistributor, Party} from "party-protocol/contracts/distribution/ITokenDistributor.sol";
import {MockTokenDistributor} from "./mock/MockTokenDistributor.t.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {MockParty} from "./mock/MockParty.t.sol";

contract ERC20CreatorV3Test is Test, MockUniswapV3Deployer {
    UniswapV3Deployment internal uniswap;
    ERC20CreatorV3 internal creator;
    ITokenDistributor internal distributor;
    Party internal party;
    FeeCollector internal feeCollector;

    event ERC20Created(
        address indexed token,
        address indexed party,
        address indexed recipient,
        string name,
        string symbol,
        uint256 ethValue,
        ERC20CreatorV3.TokenDistributionConfiguration config
    );

    function setUp() external {
        uniswap = _deployUniswapV3();
        distributor = ITokenDistributor(address(new MockTokenDistributor()));

        party = Party(payable(address(new MockParty())));
        vm.label(address(party), "Party");

        creator = new ERC20CreatorV3(
            distributor,
            INonfungiblePositionManager(uniswap.POSITION_MANAGER),
            IUniswapV3Factory(uniswap.FACTORY),
            uniswap.WETH,
            address(this),
            100
        );

        feeCollector = new FeeCollector(
            INonfungiblePositionManager(uniswap.POSITION_MANAGER),
            distributor,
            payable(this),
            IWETH(uniswap.WETH)
        );
    }

    function testCreatorV3_createToken(
        ERC20CreatorV3.TokenDistributionConfiguration memory tokenConfig,
        uint256 ethForLp
    ) public {
        tokenConfig.numTokensForDistribution = bound(
            tokenConfig.numTokensForDistribution,
            0,
            type(uint112).max
        );
        tokenConfig.numTokensForRecipient = bound(
            tokenConfig.numTokensForRecipient,
            0,
            type(uint112).max
        );
        tokenConfig.numTokensForLP = bound(
            tokenConfig.numTokensForLP,
            1e9,
            type(uint112).max
        );
        ethForLp = bound(ethForLp, 1e9, type(uint112).max);

        tokenConfig.totalSupply =
            tokenConfig.numTokensForDistribution +
            tokenConfig.numTokensForRecipient +
            tokenConfig.numTokensForLP;
        vm.assume(tokenConfig.totalSupply < type(uint112).max);

        FeeRecipient[] memory recipients = new FeeRecipient[](2);
        recipients[0] = FeeRecipient({
            recipient: address(distributor),
            percentageBps: 7_500
        });
        recipients[1] = FeeRecipient({
            recipient: address(this),
            percentageBps: 2_500
        });

        PositionData memory positionData = PositionData({
            party: party,
            recipients: recipients
        });

        vm.deal(address(party), ethForLp);

        uint256 beforeBalanceThis = address(this).balance;

        vm.expectEmit(false, true, true, true);
        emit ERC20Created(
            address(0),
            address(party),
            address(this),
            "My Test Token",
            "MTT",
            ethForLp,
            tokenConfig
        );

        vm.prank(address(party));
        IERC20 token = IERC20(
            creator.createToken{value: ethForLp}(
                address(party),
                "My Test Token",
                "MTT",
                tokenConfig,
                address(this),
                address(feeCollector),
                10_000,
                positionData
            )
        );

        address pool = creator.getPool(address(token), 10_000);

        assertEq(
            address(this).balance,
            beforeBalanceThis + (ethForLp * 100) / 10_000 // Got the fee
        );
        assertEq(
            token.balanceOf(address(this)),
            tokenConfig.numTokensForRecipient
        );
        assertEq(token.balanceOf(pool), tokenConfig.numTokensForLP);
        assertEq(
            token.balanceOf(address(distributor)),
            tokenConfig.numTokensForDistribution
        );
        assertEq(
            IERC20(uniswap.WETH).balanceOf(pool),
            ethForLp - (ethForLp * 100) / 10_000
        );

        Party party = feeCollector.getPositionData(
            MockUniswapNonfungiblePositionManager(uniswap.POSITION_MANAGER)
                .lastTokenId()
        );
        assertEq(address(party), address(party));

        FeeRecipient[] memory pulledFeeRecipients = feeCollector
            .getFeeRecipients(
                MockUniswapNonfungiblePositionManager(uniswap.POSITION_MANAGER)
                    .lastTokenId()
            );
        assertEq(pulledFeeRecipients.length, 2);
        assertEq(abi.encode(pulledFeeRecipients[0]), abi.encode(recipients[0]));
        assertEq(abi.encode(pulledFeeRecipients[1]), abi.encode(recipients[1]));

        (,bytes memory res) = address(token).call(abi.encodeWithSignature("totalSupply()"));
        uint256 totalSupply = abi.decode(res, (uint256));
        assertEq(totalSupply, tokenConfig.totalSupply);
    }

    function test_createToken_invalidPoolFeeReverts() external {
        ERC20CreatorV3.TokenDistributionConfiguration memory tokenConfig;
        PositionData memory positionData;

        vm.expectRevert(ERC20CreatorV3.InvalidPoolFee.selector);
        creator.createToken(
            address(party),
            "My Test Token",
            "MTT",
            tokenConfig,
            address(this),
            address(1),
            10_001,
            positionData
        );
    }

    function test_setFeeRecipient_error_onlyFeeRecipient() external {
        vm.expectRevert(ERC20CreatorV3.OnlyFeeRecipient.selector);
        vm.prank(address(uniswap.POSITION_MANAGER));
        creator.setFeeRecipient(address(this));
    }

    event FeeRecipientUpdated(
        address indexed oldFeeRecipient,
        address indexed newFeeRecipient
    );

    function test_setFeeRecipient_success() external {
        vm.expectEmit();
        emit FeeRecipientUpdated(address(this), address(0));
        creator.setFeeRecipient(address(0));
    }

    function test_setFeeBasisPoints_error_onlyFeeRecipient() external {
        vm.expectRevert(ERC20CreatorV3.OnlyFeeRecipient.selector);
        vm.prank(address(uniswap.POSITION_MANAGER));
        creator.setFeeBasisPoints(2_000);
    }

    event FeeBasisPointsUpdated(
        uint16 oldFeeBasisPoints,
        uint16 newFeeBasisPoints
    );

    function test_setFeeBasisPoints_success() external {
        vm.expectEmit();
        emit FeeBasisPointsUpdated(100, 200);
        creator.setFeeBasisPoints(200);
    }

    receive() external payable {}
}
