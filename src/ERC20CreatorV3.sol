// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IMulticall} from "v3-periphery/interfaces/IMulticall.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {ITokenDistributor, IERC20, Party} from "party-protocol/contracts/distribution/ITokenDistributor.sol";
import {GovernableERC20} from "./GovernableERC20.sol";
import {FeeRecipient} from "./FeeCollector.sol";

contract ERC20CreatorV3 is IERC721Receiver {
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
    error InvalidPoolFee();
    error InvalidFeeBasisPoints();

    address public immutable WETH;
    INonfungiblePositionManager public immutable UNISWAP_V3_POSITION_MANAGER;
    IUniswapV3Factory public immutable UNISWAP_V3_FACTORY;
    /// @dev Helper constant for calculating sqrtPriceX96
    uint256 private constant _X96 = 2 ** 96;

    /// @notice Fee Collector address. All LP positions transferred here
    address public immutable FEE_COLLECTOR;
    /// @notice Uniswap V3 pool fee in hundredths of a bip
    uint24 public immutable POOL_FEE;
    /// @notice The maxTick for the given pool fee
    int24 public immutable MAX_TICK;
    /// @notice The minTick for the given pool fee
    int24 public immutable MIN_TICK;
    /// @notice PartyDao token distributor contract
    ITokenDistributor public immutable TOKEN_DISTRIBUTOR;

    /// @notice Address that receives fee split of ETH at LP creation
    address public feeRecipient;
    /// @notice Fee basis points for ETH split on LP creation
    uint16 public feeBasisPoints;

    /// @param tokenDistributor PartyDao token distributor contract
    /// @param uniswapV3PositionManager Uniswap V3 position manager contract
    /// @param uniswapV3Factory Uniswap V3 factory contract
    /// @param feeCollector Fee collector address which v3 lp positions are transferred to.
    /// @param weth WETH address
    /// @param feeRecipient_ Address that receives fee split of ETH at LP creation
    /// @param feeBasisPoints_ Fee basis points for ETH split on LP creation
    /// @param poolFee Uniswap V3 pool fee in hundredths of a bip
    constructor(
        ITokenDistributor tokenDistributor,
        INonfungiblePositionManager uniswapV3PositionManager,
        IUniswapV3Factory uniswapV3Factory,
        address feeCollector,
        address weth,
        address feeRecipient_,
        uint16 feeBasisPoints_,
        uint16 poolFee
    ) {
        if (poolFee != 500 && poolFee != 3000 && poolFee != 10_000)
            revert InvalidPoolFee();
        if (feeBasisPoints_ > 5e3) revert InvalidFeeBasisPoints();

        TOKEN_DISTRIBUTOR = tokenDistributor;
        UNISWAP_V3_POSITION_MANAGER = uniswapV3PositionManager;
        UNISWAP_V3_FACTORY = uniswapV3Factory;
        WETH = weth;
        feeRecipient = feeRecipient_;
        feeBasisPoints = feeBasisPoints_;
        POOL_FEE = poolFee;
        FEE_COLLECTOR = feeCollector;

        int24 tickSpacing = UNISWAP_V3_FACTORY.feeAmountTickSpacing(POOL_FEE);
        MAX_TICK = (887272 /* TickMath.MAX_TICK */ / tickSpacing) * tickSpacing;
        MIN_TICK =
            (-887272 /* TickMath.MIN_TICK */ / tickSpacing) *
            tickSpacing;
    }

    /// @notice Creates a new ERC20 token, LPs it in a locked full range Uniswap V3 position, and distributes some of the new token to party members.
    /// @dev The party is assumed to be `msg.sender`
    /// @param party The party to allocate this token to
    /// @param name The name of the new token
    /// @param symbol The symbol of the new token
    /// @param config Token distribution configuration. See above for additional information.
    /// @param tokenRecipientAddress The address to receive the tokens allocated for the token recipient
    /// @param partyDaoFeeBps The fee basis points for PartyDAO upon fee collection
    /// @return token The address of the newly created token
    function createToken(
        address party,
        string memory name,
        string memory symbol,
        TokenDistributionConfiguration memory config,
        address tokenRecipientAddress,
        uint16 partyDaoFeeBps
    ) external payable returns (address) {
        // Require that tokens are fully distributed
        if (
            config.numTokensForDistribution +
                config.numTokensForRecipient +
                config.numTokensForLP !=
            config.totalSupply ||
            config.totalSupply > type(uint112).max
        ) {
            revert InvalidTokenDistribution();
        }

        // We use a changing salt to ensure address changes every block. If the LP position already exists, the TX will revert.
        // Can be tried again the next block.
        IERC20 token = IERC20(
            address(
                new GovernableERC20{
                    salt: keccak256(
                        abi.encode(blockhash(block.number - 1), msg.sender)
                    )
                }(name, symbol, config.totalSupply, address(this))
            )
        );

        if (config.numTokensForDistribution > 0) {
            // Create distribution
            token.transfer(
                address(TOKEN_DISTRIBUTOR),
                config.numTokensForDistribution
            );
            TOKEN_DISTRIBUTOR.createErc20Distribution(
                token,
                Party(payable(party)),
                payable(address(0)),
                0
            );
        }

        // Take fee
        uint256 feeAmount = (msg.value * feeBasisPoints) / 1e4;

        // The id of the LP nft
        uint256 lpTokenId;

        {
            (address token0, address token1) = WETH < address(token)
                ? (WETH, address(token))
                : (address(token), WETH);
            (uint256 amount0, uint256 amount1) = WETH < address(token)
                ? (msg.value - feeAmount, config.numTokensForLP)
                : (config.numTokensForLP, msg.value - feeAmount);

            // Create and initialize pool. Reverts if pool already created.
            address pool = UNISWAP_V3_FACTORY.createPool(
                address(token),
                WETH,
                POOL_FEE
            );

            // Initialize pool for the derived starting price
            uint160 sqrtPriceX96 = uint160(
                (Math.sqrt((amount1 * 1e18) / amount0) * _X96) / 1e9
            );
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);

            token.approve(
                address(UNISWAP_V3_POSITION_MANAGER),
                config.numTokensForLP
            );

            // Use multicall to sweep back excess ETH
            bytes[] memory calls = new bytes[](2);
            calls[0] = abi.encodeCall(
                UNISWAP_V3_POSITION_MANAGER.mint,
                (
                    INonfungiblePositionManager.MintParams({
                        token0: token0,
                        token1: token1,
                        fee: POOL_FEE,
                        tickLower: MIN_TICK,
                        tickUpper: MAX_TICK,
                        amount0Desired: amount0,
                        amount1Desired: amount1,
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(this),
                        deadline: block.timestamp
                    })
                )
            );
            calls[1] = abi.encodePacked(
                UNISWAP_V3_POSITION_MANAGER.refundETH.selector
            );
            bytes memory mintReturnData = IMulticall(
                address(UNISWAP_V3_POSITION_MANAGER)
            ).multicall{value: msg.value - feeAmount}(calls)[0];

            lpTokenId = abi.decode(mintReturnData, (uint256));
        }

        // Transfer tokens to token recipient
        if (config.numTokensForRecipient > 0) {
            token.transfer(tokenRecipientAddress, config.numTokensForRecipient);
        }

        // Refund any remaining dust of the token to the party
        {
            uint256 remainingTokenBalance = token.balanceOf(address(this));
            if (remainingTokenBalance > 0) {
                // Adjust the numTokensForLP to reflect the actual amount used
                config.numTokensForLP -= remainingTokenBalance;
                token.transfer(party, remainingTokenBalance);
            }
        }

        // Transfer fee
        if (feeAmount > 0) {
            feeRecipient.call{value: feeAmount, gas: 100_000}("");
        }

        // Transfer remaining ETH to the party
        if (address(this).balance > 0) {
            payable(party).call{value: address(this).balance, gas: 100_000}("");
        }

        FeeRecipient[] memory recipients = new FeeRecipient[](1);
        recipients[0] = FeeRecipient({
            recipient: payable(party),
            percentageBps: 10_000
        });

        // Transfer LP to fee collector contract
        UNISWAP_V3_POSITION_MANAGER.safeTransferFrom(
            address(this),
            FEE_COLLECTOR,
            lpTokenId,
            abi.encode(recipients, partyDaoFeeBps)
        );

        emit ERC20Created(
            address(token),
            party,
            tokenRecipientAddress,
            name,
            symbol,
            msg.value,
            config
        );

        return address(token);
    }

    /// @notice Get the Uniswap V3 pool for a token
    function getPool(address token) external view returns (address) {
        return UNISWAP_V3_FACTORY.getPool(token, WETH, POOL_FEE);
    }

    /// @notice Sets the fee recipient for ETH split on LP creation
    function setFeeRecipient(address feeRecipient_) external {
        address oldFeeRecipient = feeRecipient;

        if (msg.sender != oldFeeRecipient) revert OnlyFeeRecipient();
        feeRecipient = feeRecipient_;

        emit FeeRecipientUpdated(oldFeeRecipient, feeRecipient_);
    }

    /// @notice Sets the fee basis points for ETH split on LP creation
    /// @param feeBasisPoints_ The new fee basis points in basis points
    function setFeeBasisPoints(uint16 feeBasisPoints_) external {
        if (msg.sender != feeRecipient) revert OnlyFeeRecipient();
        if (feeBasisPoints_ > 5e3) revert InvalidFeeBasisPoints();
        emit FeeBasisPointsUpdated(feeBasisPoints, feeBasisPoints_);

        feeBasisPoints = feeBasisPoints_;
    }

    /// @notice Allow contract to receive refund from position manager
    receive() external payable {}

    /// @notice Allow for Uniswap V3 lp position to be received
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
