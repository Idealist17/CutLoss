// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {GuardianStopLoss} from "../src/GuardianStopLoss.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployGuardian is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Sepolia addresses (Defaults)
        address chainlinkFeed = vm.envOr("CHAINLINK_FEED", 0x694AA1769357215DE4FAC081bf1f309aDC325306);
        address uniswapPool = vm.envOr("UNISWAP_POOL", 0x6Ce0896eAE6D4BD668fDe41BB784548fb8F59b50); 
        // Default to the Universal Router address requested by user
        address swapRouter = vm.envOr("SWAP_ROUTER", 0xE592427A0AEce92De3Edee1F18E0157C05861564);
        address usdcToken = vm.envOr("USDC_TOKEN", 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        uint256 bountyPercentage = vm.envOr("BOUNTY_PERCENTAGE", uint256(100));

        vm.startBroadcast(deployerPrivateKey);

        // Check if SwapRouter exists, if not deploy it
        if (swapRouter.code.length == 0) {
            console.log("SwapRouter not found at", swapRouter);
            console.log("Deploying new SwapRouter...");
            
            // Sepolia Factory and WETH
            address factory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
            address weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
            
            // Manually read artifact to bypass deployCode issues
            string memory artifact = vm.readFile("out/SwapRouter.sol/SwapRouter.json");
            bytes memory bytecode = vm.parseJsonBytes(artifact, ".bytecode.object");
            bytes memory args = abi.encode(factory, weth);
            bytes memory combinedBytecode = abi.encodePacked(bytecode, args);
            
            address newRouter;
            assembly {
                newRouter := create(0, add(combinedBytecode, 0x20), mload(combinedBytecode))
            }
            require(newRouter != address(0), "Deployment failed");
            
            swapRouter = newRouter;
            console.log("New SwapRouter deployed at:", swapRouter);
        } else {
            console.log("Using existing SwapRouter at:", swapRouter);
        }

        // Implementation
        GuardianStopLoss implementation = new GuardianStopLoss();
        console.log("Implementation deployed at:", address(implementation));

        // Initialize data
        bytes memory data = abi.encodeWithSelector(
            GuardianStopLoss.initialize.selector,
            chainlinkFeed,
            uniswapPool,
            swapRouter,
            usdcToken,
            bountyPercentage
        );

        // Proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        console.log("GuardianStopLoss Proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
