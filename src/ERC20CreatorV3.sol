// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MathLib} from "./utils/MathLib.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/interfaces/IMulticall.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {ITokenDistributor, IERC20, Party} from "party-protocol/contracts/distribution/ITokenDistributor.sol";
import {GovernableERC20, ERC20} from "./GovernableERC20.sol";

contract ERC20CreatorV3 {
    using MathLib for uint256;

    event ERC20Created(
        address indexed token,
        address indexed party,
        address recipient,
        TokenConfiguration config
    );

    event FeeRecipientUpdated(
        address indexed oldFeeRecipient,
        address indexed newFeeRecipient
    );
    event FeeBasisPointsUpdated(
        uint16 oldFeeBasisPoints,
        uint16 newFeeBasisPoints
    );

    error InvalidTokenDistribution();
    error OnlyFeeRecipient();

    uint24 internal constant POOL_FEE = 10_000; // 1% fee
    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;
    INonfungiblePositionManager public immutable UNISWAP_V3_POSITION_MANAGER;
    IUniswapV3Factory public immutable UNISWAP_V3_FACTORY;
    address public immutable WETH;
    uint256 private constant X96 = 2 ** 96;

    address public feeRecipient;
    uint16 public feeBasisPoints;

    struct TokenConfiguration {
        uint256 totalSupply;
        uint256 numTokensForDistribution;
        uint256 numTokensForRecipient;
        uint256 numTokensForLP;
    }

    constructor(
        ITokenDistributor _tokenDistributor,
        INonfungiblePositionManager _uniswapV3PositionManager,
        IUniswapV3Factory _uniswapV3Factory,
        address _weth,
        address _feeRecipient,
        uint16 _feeBasisPoints
    ) {
        TOKEN_DISTRIBUTOR = _tokenDistributor;
        UNISWAP_V3_POSITION_MANAGER = _uniswapV3PositionManager;
        UNISWAP_V3_FACTORY = _uniswapV3Factory;
        WETH = _weth;
        feeRecipient = _feeRecipient;
        feeBasisPoints = _feeBasisPoints;
    }

    function createToken(
        address partyAddress,
        string calldata name,
        string calldata symbol,
        TokenConfiguration calldata config,
        address tokenRecipientAddress,
        address lpRecipientAddress
    ) external payable returns (ERC20 token) {
        if (
            config.numTokensForDistribution +
                config.numTokensForRecipient +
                config.numTokensForLP !=
            config.totalSupply ||
            config.totalSupply > type(uint112).max
        ) {
            revert InvalidTokenDistribution();
        }

        // Create token
        token = new GovernableERC20{
            salt: keccak256(abi.encode(blockhash(block.number), msg.sender))
        }(name, symbol, config.totalSupply, address(this));

        if (config.numTokensForDistribution > 0) {
            // Create distribution
            token.transfer(
                address(TOKEN_DISTRIBUTOR),
                config.numTokensForDistribution
            );
            TOKEN_DISTRIBUTOR.createErc20Distribution(
                IERC20(address(token)),
                Party(payable(partyAddress)),
                payable(address(0)),
                0
            );
        }

        // Take fee
        uint256 ethValue = msg.value;
        uint256 feeAmount = (ethValue * feeBasisPoints) / 1e4;

        // Create locked LP pair
        uint256 numETHForLP = ethValue - feeAmount;

        // Create and initialize pool. Reverts if pool already created.
        address pool = UNISWAP_V3_FACTORY.createPool(
            address(token),
            WETH,
            POOL_FEE
        );

        uint160 sqrtPriceX96 = uint160(
            (((numETHForLP * 1e18) / config.numTokensForLP).sqrt() * X96) / 1e9
        );

        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        token.approve(
            address(UNISWAP_V3_POSITION_MANAGER),
            config.numTokensForLP
        );

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            UNISWAP_V3_POSITION_MANAGER.mint,
            (
                INonfungiblePositionManager.MintParams({
                    token0: address(token),
                    token1: WETH,
                    fee: POOL_FEE,
                    tickLower: -887200,
                    tickUpper: 887200,
                    amount0Desired: config.numTokensForLP,
                    amount1Desired: numETHForLP,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: lpRecipientAddress,
                    deadline: block.timestamp
                })
            )
        );
        calls[1] = abi.encodePacked(
            UNISWAP_V3_POSITION_MANAGER.refundETH.selector
        );

        IMulticall(address(UNISWAP_V3_POSITION_MANAGER)).multicall{
            value: numETHForLP
        }(calls);

        // Transfer tokens to token recipient
        token.transfer(tokenRecipientAddress, config.numTokensForRecipient);

        // Transfer fee
        feeRecipient.call{value: feeAmount, gas: 100_000}("");

        // Transfer remaining ETH to the party
        msg.sender.call{value: address(this).balance}("");

        emit ERC20Created(
            address(token),
            partyAddress,
            tokenRecipientAddress,
            config
        );
    }

    function getPool(address token) external view returns (address) {
        return UNISWAP_V3_FACTORY.getPool(token, WETH, POOL_FEE);
    }

    function setFeeRecipient(address _feeRecipient) external {
        address oldFeeRecipient = feeRecipient;
        if (msg.sender != oldFeeRecipient) revert OnlyFeeRecipient();
        emit FeeRecipientUpdated(oldFeeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setFeeBasisPoints(uint16 _feeBasisPoints) external {
        if (msg.sender != feeRecipient) revert OnlyFeeRecipient();
        emit FeeBasisPointsUpdated(feeBasisPoints, _feeBasisPoints);
        feeBasisPoints = _feeBasisPoints;
    }

    receive() external payable {}
}
