// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MathLib} from "./utils/MathLib.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/interfaces/IMulticall.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ITokenDistributor, IERC20, Party} from "party-protocol/contracts/distribution/ITokenDistributor.sol";
import {GovernableERC20} from "./GovernableERC20.sol";

contract ERC20CreatorV3 is IERC721Receiver {
    using MathLib for uint256;

    struct TokenDistributionConfiguration {
        uint256 totalSupply; // Total supply of the token
        uint256 numTokensForDistribution; // Number of tokens to distribute to the party
        uint256 numTokensForRecipient; // Number of tokens to send to the `tokenRecipient`
        uint256 numTokensForLP; // Number of tokens for the Uniswap V3 LP
    }

    event ERC20Created(
        address indexed token,
        address indexed party,
        address indexed recipient,
        string name,
        string symbol,
        uint256 ethValue,
        TokenDistributionConfiguration config
    );

    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    event FeeBasisPointsUpdated(uint16 oldFeeBasisPoints, uint16 newFeeBasisPoints);

    error InvalidTokenDistribution();
    error OnlyFeeRecipient();
    error InvalidPoolFee();

    /// @notice Delete once can be imported
    struct FeeRecipient {
        address recipient;
        uint16 percentageBps;
    }
    /// @notice Delete once can be imported

    struct PositionData {
        Party party;
        uint40 lastCollectTimestamp;
        bool isFirstRecipientDistributor;
        FeeRecipient[] recipients;
    }

    INonfungiblePositionManager public immutable UNISWAP_V3_POSITION_MANAGER;
    IUniswapV3Factory public immutable UNISWAP_V3_FACTORY;
    /// @dev Helper constant for calculating sqrtPriceX96
    uint256 private constant _X96 = 2 ** 96;

    /// @notice PartyDao token distributor contract
    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;
    address public immutable WETH;

    /// @notice Address that receives fee split of ETH at LP creation
    address public feeRecipient;
    /// @notice Fee basis points for ETH split on LP creation
    uint16 public feeBasisPoints;

    /// @param _tokenDistributor PartyDao token distributor contract
    /// @param _uniswapV3PositionManager Uniswap V3 position manager contract
    /// @param _uniswapV3Factory Uniswap V3 factory contract
    /// @param _weth WETH address
    /// @param _feeRecipient Address that receives fee split of ETH at LP creation
    /// @param _feeBasisPoints Fee basis points for ETH split on LP creation
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

    /// @notice Creates a new ERC20 token, LPs it in a locked full range Uniswap V3 position, and distributes some of the new token to party members.
    /// @dev The party is assumed to be `msg.sender`
    /// @param name The name of the new token
    /// @param symbol The symbol of the new token
    /// @param config Token distribution configuration. See above for additional information.
    /// @param tokenRecipientAddress The address to receive the tokens allocated for the token recipient
    /// @param feeCollectorAddress Fee collector address where the LP will get locked
    /// @param poolFee Pool swap fee in hundredths of a basis point. This MUST be 500, 3_000, or 10_000
    /// @return token The address of the newly created token
    function createToken(
        string memory name,
        string memory symbol,
        TokenDistributionConfiguration memory config,
        address tokenRecipientAddress,
        address feeCollectorAddress,
        uint16 poolFee,
        PositionData calldata positionData
    ) external payable returns (address) {
        // Require that tokens are fully distributed
        if (
            config.numTokensForDistribution + config.numTokensForRecipient + config.numTokensForLP != config.totalSupply
                || config.totalSupply > type(uint112).max
        ) {
            revert InvalidTokenDistribution();
        }

        // Only fees currently supported by uniswap
        if(poolFee != 500 && poolFee != 3_000 && poolFee != 10_000) {
            revert InvalidPoolFee();
        }

        // We use a changing salt to ensure address changes every block. If the LP position already exists, the TX will revert.
        // Can be tried again the next block.
        IERC20 token = IERC20(
            address(
                new GovernableERC20{salt: keccak256(abi.encode(blockhash(block.number), msg.sender))}(
                    name, symbol, config.totalSupply, address(this)
                )
            )
        );

        if (config.numTokensForDistribution > 0) {
            // Create distribution
            token.transfer(address(TOKEN_DISTRIBUTOR), config.numTokensForDistribution);
            TOKEN_DISTRIBUTOR.createErc20Distribution(token, Party(payable(msg.sender)), payable(address(0)), 0);
        }

        // Take fee
        uint256 feeAmount = (msg.value * feeBasisPoints) / 1e4;

        {
            // Create and initialize pool. Reverts if pool already created.
            address pool = UNISWAP_V3_FACTORY.createPool(address(token), WETH, poolFee);

            // Initialize pool for the derived starting price
            uint160 sqrtPriceX96 =
                uint160(((((msg.value - feeAmount) * 1e18) / config.numTokensForLP).sqrt() * _X96) / 1e9);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        }

        token.approve(address(UNISWAP_V3_POSITION_MANAGER), config.numTokensForLP);

        // The id of the LP nft
        uint256 lpTokenId;
        {
            // Use multicall to sweep back excess ETH
            bytes[] memory calls = new bytes[](2);
            calls[0] = abi.encodeCall(
                UNISWAP_V3_POSITION_MANAGER.mint,
                (
                    INonfungiblePositionManager.MintParams({
                        token0: address(token),
                        token1: WETH,
                        fee: poolFee,
                        tickLower: int24(poolFee == 3_000 ? -887220 : -887200),
                        tickUpper: int24(poolFee == 3_000 ? 887220 : 887200),
                        amount0Desired: config.numTokensForLP,
                        amount1Desired: msg.value - feeAmount,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(this),
                        deadline: block.timestamp
                    })
                )
            );
            calls[1] = abi.encodePacked(UNISWAP_V3_POSITION_MANAGER.refundETH.selector);
            bytes memory mintReturnData =
                IMulticall(address(UNISWAP_V3_POSITION_MANAGER)).multicall{value: msg.value - feeAmount}(calls)[0];

            lpTokenId = abi.decode(mintReturnData, (uint256));
        }

        // Transfer tokens to token recipient
        if (config.numTokensForRecipient > 0) {
            token.transfer(tokenRecipientAddress, config.numTokensForRecipient);
        }

        // Transfer fee
        if (feeAmount > 0) {
            feeRecipient.call{value: feeAmount, gas: 100_000}("");
        }

        // Transfer remaining ETH to the party
        if (address(this).balance > 0) {
            payable(msg.sender).call{value: address(this).balance}("");
        }

        // Transfer LP to fee collector contract
        UNISWAP_V3_POSITION_MANAGER.safeTransferFrom(
            address(this), feeCollectorAddress, lpTokenId, abi.encode(positionData)
        );

        emit ERC20Created(address(token), msg.sender, tokenRecipientAddress, name, symbol, msg.value, config);

        return address(token);
    }

    /// @notice Get the Uniswap V3 pool for a token
    function getPool(address token, uint16 poolFee) external view returns (address) {
        return UNISWAP_V3_FACTORY.getPool(token, WETH, poolFee);
    }

    /// @notice Sets the fee recipient for ETH split on LP creation
    function setFeeRecipient(address _feeRecipient) external {
        address oldFeeRecipient = feeRecipient;

        if (msg.sender != oldFeeRecipient) revert OnlyFeeRecipient();
        feeRecipient = _feeRecipient;

        emit FeeRecipientUpdated(oldFeeRecipient, _feeRecipient);
    }

    /// @notice Sets the fee basis points for ETH split on LP creation
    /// @param _feeBasisPoints The new fee basis points in basis points
    function setFeeBasisPoints(uint16 _feeBasisPoints) external {
        if (msg.sender != feeRecipient) revert OnlyFeeRecipient();
        emit FeeBasisPointsUpdated(feeBasisPoints, _feeBasisPoints);

        feeBasisPoints = _feeBasisPoints;
    }

    /// @notice Allow contract to receive refund from position manager
    receive() external payable {}

    /// @notice Allow for Uniswap V3 lp position to be received
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
