// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";
import {MockUniswapV3Deployer} from "./mock/MockUniswapV3Deployer.t.sol";
import {ERC20CreatorV3, IERC20, FeeRecipient} from "src/ERC20CreatorV3.sol";
import {FeeCollector, IWETH} from "src/FeeCollector.sol";
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

        feeCollector = new FeeCollector(
            INonfungiblePositionManager(uniswap.POSITION_MANAGER),
            payable(this),
            IWETH(uniswap.WETH)
        );

        creator = new ERC20CreatorV3(
            distributor,
            INonfungiblePositionManager(uniswap.POSITION_MANAGER),
            IUniswapV3Factory(uniswap.FACTORY),
            address(feeCollector),
            uniswap.WETH,
            address(this),
            100,
            10_000
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
        vm.assume(
            tokenConfig.totalSupply < type(uint112).max &&
                tokenConfig.totalSupply > 0
        );

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
                address(this)
            )
        );

        address pool = creator.getPool(address(token));

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

        FeeRecipient[] memory feeRecipients = feeCollector.getFeeRecipients(
            MockUniswapNonfungiblePositionManager(uniswap.POSITION_MANAGER)
                .lastTokenId()
        );
        assertEq(feeRecipients.length, 1);
        assertEq(
            abi.encode(feeRecipients[0]),
            abi.encode(
                FeeRecipient({recipient: address(party), percentageBps: 10_000})
            )
        );

        (, bytes memory res) = address(token).call(
            abi.encodeWithSignature("totalSupply()")
        );
        uint256 totalSupply = abi.decode(res, (uint256));
        assertEq(totalSupply, tokenConfig.totalSupply);
    }

    function test_constructor_invalidPoolFeeReverts() external {
        ERC20CreatorV3.TokenDistributionConfiguration memory tokenConfig;

        vm.expectRevert(ERC20CreatorV3.InvalidPoolFee.selector);
        creator = new ERC20CreatorV3(
            distributor,
            INonfungiblePositionManager(uniswap.POSITION_MANAGER),
            IUniswapV3Factory(uniswap.FACTORY),
            address(feeCollector),
            uniswap.WETH,
            address(this),
            100,
            10_001
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
