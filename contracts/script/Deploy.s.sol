// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../PredictionMarket.sol";

/**
 * @title DeployScript
 * @dev Deployment script for PredictionMarket contract
 */
contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PredictionMarket
        PredictionMarket market = new PredictionMarket(usdcAddress);

        vm.stopBroadcast();

        console.log("PredictionMarket deployed to:", address(market));
        console.log("USDC Address:", usdcAddress);
        console.log("Deployer:", msg.sender);
    }
}

/**
 * @title DeployWithSetupScript
 * @dev Deployment script with initial setup (authorize relayer, deposit liquidity)
 */
contract DeployWithSetupScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address relayerAddress = vm.envAddress("RELAYER_ADDRESS");
        uint256 initialLiquidity = vm.envUint("INITIAL_LIQUIDITY"); // in USDC (with decimals)

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PredictionMarket
        PredictionMarket market = new PredictionMarket(usdcAddress);
        console.log("PredictionMarket deployed to:", address(market));

        // 2. Authorize relayer
        market.setRelayerAuthorization(relayerAddress, true);
        console.log("Relayer authorized:", relayerAddress);

        // 3. Deposit initial liquidity (if specified)
        if (initialLiquidity > 0) {
            IERC20(usdcAddress).transfer(address(market), initialLiquidity);
            console.log("Initial liquidity deposited:", initialLiquidity);
        }

        vm.stopBroadcast();

        // Output deployment info
        console.log("=== Deployment Complete ===");
        console.log("Market Address:", address(market));
        console.log("USDC Address:", usdcAddress);
        console.log("Relayer:", relayerAddress);
        console.log("Owner:", msg.sender);
    }
}
