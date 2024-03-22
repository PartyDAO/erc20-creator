// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import "./../lib/party-protocol/contracts/distribution/ITokenDistributor.sol";
import {GovernableERC20, ERC20} from "./GovernableERC20.sol";

contract ERC20CreatorV3 {
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
            config.totalSupply
        ) {
            revert InvalidTokenDistribution();
        }

        // Create token
        token = new GovernableERC20(
            name,
            symbol,
            config.totalSupply,
            address(this)
        );

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

        // Take fee
        uint256 ethValue = msg.value;
        uint256 feeAmount = (ethValue * feeBasisPoints) / 1e4;
        payable(feeRecipient).transfer(feeAmount);

        // Create locked LP pair
        uint256 numETHForLP = ethValue - feeAmount;

        // Create and initialize pool
        address pool = UNISWAP_V3_FACTORY.createPool(
            address(token),
            WETH,
            POOL_FEE
        );

        uint160 sqrtPriceX96 = uint160((sqrt(
            (numETHForLP * 1e18) / config.numTokensForLP
        ) * X96) / 1e9);

        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        token.approve(
            address(UNISWAP_V3_POSITION_MANAGER),
            config.numTokensForLP
        );

        // TODO: claim excess eth
        UNISWAP_V3_POSITION_MANAGER.mint{value: numETHForLP}(
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
        );

        // Transfer tokens to token recipient
        token.transfer(tokenRecipientAddress, config.numTokensForRecipient);

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

    function sqrt(uint256 x) public pure returns (uint128) {
        if (x == 0) return 0;
        else {
            uint256 xx = x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) {
                xx >>= 128;
                r <<= 64;
            }
            if (xx >= 0x10000000000000000) {
                xx >>= 64;
                r <<= 32;
            }
            if (xx >= 0x100000000) {
                xx >>= 32;
                r <<= 16;
            }
            if (xx >= 0x10000) {
                xx >>= 16;
                r <<= 8;
            }
            if (xx >= 0x100) {
                xx >>= 8;
                r <<= 4;
            }
            if (xx >= 0x10) {
                xx >>= 4;
                r <<= 2;
            }
            if (xx >= 0x8) {
                r <<= 1;
            }
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            uint256 r1 = x / r;
            return uint128(r < r1 ? r : r1);
        }
    }
}
