// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {GuardianStopLoss} from "../src/GuardianStopLoss.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GuardianTest is Test {
    GuardianStopLoss public guardian;
    address public implementation;
    address public proxy;
    
    // Mainnet addresses
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant UNISWAP_POOL_ETH_USDC = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8; // 0.3%
    address public constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    address public user = makeAddr("user");
    address public keeper = makeAddr("keeper");

    function setUp() public {
        // Fork Mainnet
        string memory rpcUrl = vm.envOr("RPC_URL", string("https://1rpc.io/eth"));
        vm.createSelectFork(rpcUrl);

        implementation = address(new GuardianStopLoss());
        
        bytes memory initData = abi.encodeWithSelector(
            GuardianStopLoss.initialize.selector,
            CHAINLINK_ETH_USD,
            UNISWAP_POOL_ETH_USDC,
            SWAP_ROUTER,
            USDC,
            100 // 1% bounty
        );

        proxy = address(new ERC1967Proxy(implementation, initData));
        guardian = GuardianStopLoss(payable(proxy));
        
        // Fund user
        vm.deal(user, 100 ether);
    }

    function testHappyPath() public {
        // 1. User creates order
        uint256 stopLossPrice = 5000 * 1e8; // High price to ensure it triggers if we drop to 2900
        vm.prank(user);
        guardian.createOrder{value: 1 ether}(stopLossPrice);

        // 2. Mock Price Drop (Chainlink)
        mockChainlinkPrice(2900 * 1e8);

        // 3. Keeper executes
        vm.prank(keeper);
        guardian.executeOrder(0);

        // 4. Verify
        // User should have USDC
        uint256 userUsdc = IERC20(USDC).balanceOf(user);
        uint256 keeperUsdc = IERC20(USDC).balanceOf(keeper);
        
        console.log("User USDC:", userUsdc);
        console.log("Keeper Bounty:", keeperUsdc);
        
        assertTrue(userUsdc > 0, "User should receive USDC");
        assertTrue(keeperUsdc > 0, "Keeper should receive bounty");
    }

    function testSecurity() public {
        address newImplementation = address(new GuardianStopLoss());
        
        // Non-owner cannot upgrade
        vm.prank(user);
        vm.expectRevert();
        guardian.upgradeToAndCall(newImplementation, "");       
        guardian.upgradeToAndCall(newImplementation, "");
    }
    
    function mockChainlinkPrice(int256 price) internal {
        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), price, uint256(0), block.timestamp, uint80(1))
        );
    }

    function mockChainlinkStale() internal {
        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000 * 1e8), uint256(0), block.timestamp - 2 hours, uint80(1))
        );
    }
        function testOracleFailure() public {
        // 1. User creates order
        // We use a very high stop loss price to ensure TWAP (whatever it is) triggers it
        uint256 stopLossPrice = 100000 * 1e8; 
        vm.prank(user);
        guardian.createOrder{value: 1 ether}(stopLossPrice);
        
        (uint256 id, address u, uint256 amt, uint256 sl, bool active) = guardian.orders(0);
        console.log("Order 0 Active:", active);
        console.log("Order 0 User:", u);

        // 2. Mock Chainlink Failure (Stale)
        mockChainlinkStale();

        // 3. Verify Fallback to TWAP
        // We check that getCrossCheckPrice returns a value (TWAP)
        uint256 twapPrice = guardian.getCrossCheckPrice();
        console.log("TWAP Price:", twapPrice);
        assertTrue(twapPrice > 0, "TWAP price should be > 0");

        vm.prank(keeper);
        guardian.executeOrder(0); // Order ID 0 because fresh setup
        
        assertTrue(IERC20(USDC).balanceOf(user) > 0, "User should receive USDC via TWAP fallback");
    }
}
