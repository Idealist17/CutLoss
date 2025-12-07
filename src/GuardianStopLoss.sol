// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "./libraries/OracleLibrary.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract GuardianStopLoss is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, PausableUpgradeable {
    struct Order {
        uint256 id;
        address user;
        uint256 amount; // ETH amount
        uint256 stopLossPrice; // In USD (Chainlink decimals usually 8)
        bool isActive;
    }

    AggregatorV3Interface public priceFeed;
    IUniswapV3Pool public uniswapPool;
    ISwapRouter public swapRouter;
    address public usdcToken;
    uint256 public bountyPercentage; // bps, e.g., 100 = 1%

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;

    // Gap for upgradeability
    uint256[50] private __gap;

    event OrderCreated(uint256 indexed orderId, address indexed user, uint256 amount, uint256 stopLossPrice);
    event OrderExecuted(uint256 indexed orderId, address indexed keeper, uint256 executedPrice, uint256 bounty, uint256 userAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _priceFeed,
        address _uniswapPool,
        address _swapRouter,
        address _usdcToken,
        uint256 _bountyPercentage
    ) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();

        priceFeed = AggregatorV3Interface(_priceFeed);
        uniswapPool = IUniswapV3Pool(_uniswapPool);
        swapRouter = ISwapRouter(_swapRouter);
        usdcToken = _usdcToken;
        bountyPercentage = _bountyPercentage;
    }
    
    /// @dev Required by the UUPS module. Authorization logic is handled by the `onlyOwner` modifier.
    ///      This ensures that only the owner can upgrade the contract implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getCrossCheckPrice() public view returns (uint256) {
        // Step 1: Chainlink
        try priceFeed.latestRoundData() returns (
            uint80 /* roundId */,
            int256 price,
            uint256 /* startedAt */,
            uint256 updatedAt,
            uint80 /* answeredInRound */
        ) {
            if (price > 0 && block.timestamp - updatedAt < 1 hours) {
                return uint256(price); // Assumes 8 decimals
            }
        } catch {}

        // Step 2: Fallback to Uniswap TWAP
        // TWAP for 30 mins
        uint32 secondsAgo = 1800;
        
        // OracleLibrary.consult returns arithmetic mean tick
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(address(uniswapPool), secondsAgo);
        
        address token0 = uniswapPool.token0();
        address token1 = uniswapPool.token1();
        address weth = token0 == usdcToken ? token1 : token0;

        // Calculate quote amount for 1 ETH (1e18)
        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            1e18, // 1 ETH
            weth, // base token
            usdcToken // quote token
        );
        
        // Uniswap quote is in USDC decimals (6). Chainlink is 8.
        // We need to normalize to Chainlink decimals (8).
        // 1e6 -> 1e8 requires * 100.
        return quoteAmount * 100;
    }

    function createOrder(uint256 stopLossPrice) external payable {
        require(msg.value > 0, "No ETH sent");
        uint256 orderId = nextOrderId++;
        orders[orderId] = Order({
            id: orderId,
            user: msg.sender,
            amount: msg.value,
            stopLossPrice: stopLossPrice,
            isActive: true
        });
        emit OrderCreated(orderId, msg.sender, msg.value, stopLossPrice);
    }

    function executeOrder(uint256 orderId) external nonReentrant whenNotPaused {
        Order storage order = orders[orderId];
        require(order.isActive, "Order not active");
        require(order.user != address(0), "Order does not exist");

        uint256 currentPrice = getCrossCheckPrice();
        require(currentPrice <= order.stopLossPrice, "Price not below stop loss");
        
        order.isActive = false;

        // Wrap ETH to WETH
        address token0 = uniswapPool.token0();
        address token1 = uniswapPool.token1();
        address weth = token0 == usdcToken ? token1 : token0;
        
        (bool success, ) = weth.call{value: order.amount}(abi.encodeWithSignature("deposit()"));
        require(success, "WETH wrap failed");
        
        // Approve Router
        IERC20(weth).approve(address(swapRouter), order.amount);
        
        // Swap
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: usdcToken,
                fee: uniswapPool.fee(),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: order.amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = swapRouter.exactInputSingle(params);

        // Incentive
        uint256 bounty = (amountOut * bountyPercentage) / 10000;
        uint256 userAmount = amountOut - bounty;

        // Transfer
        require(IERC20(usdcToken).transfer(msg.sender, bounty), "Bounty transfer failed");
        require(IERC20(usdcToken).transfer(order.user, userAmount), "User transfer failed");
        
        emit OrderExecuted(orderId, msg.sender, currentPrice, bounty, userAmount);
    }
    
    receive() external payable {}
}
