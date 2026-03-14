// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ConditionalToken.sol";
import "./MockUSDC.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );

        vm.startBroadcast(deployerPrivateKey);

        console.log("========================================");
        console.log("  Polymarket Contract Deployment");
        console.log("========================================");

        console.log("\n[1/2] Deploying MockUSDC...");
        MockUSDC mockUSDC = new MockUSDC();
        address mockUSDCAddress = address(mockUSDC);
        console.log("MockUSDC address:", mockUSDCAddress);

        console.log("\n[2/2] Deploying ConditionalToken...");
        ConditionalToken conditionalToken = new ConditionalToken(mockUSDCAddress);
        address conditionalTokenAddress = address(conditionalToken);
        console.log("ConditionalToken address:", conditionalTokenAddress);

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  Deployment Complete!");
        console.log("========================================");
        console.log("MockUSDC:", mockUSDCAddress);
        console.log("ConditionalToken:", conditionalTokenAddress);

        _generateConfig(mockUSDCAddress, conditionalTokenAddress);
    }

    function _generateConfig(address usdcAddress, address tokenAddress) internal {
        string memory json = string.concat(
            '{"mockUSDC":"', vm.toString(usdcAddress), '",',
            '"conditionalToken":"', vm.toString(tokenAddress), '",',
            '"network":"anvil",',
            '"chainId":31337}'
        );
        vm.writeJson(json, "deployments/latest.json");

        string memory javaConfig = string.concat(
            "# Auto-generated contract config\n",
            "polymarket.contract.address=",
            vm.toString(tokenAddress),
            "\n",
            "polymarket.usdc.address=",
            vm.toString(usdcAddress),
            "\n",
            "polymarket.rpc.url=http://localhost:8545\n",
            "polymarket.chain.id=31337\n"
        );
        vm.writeFile(javaConfig, "deployments/application-contract.yml");

        string memory frontendConfig = string.concat(
            "# Auto-generated contract config\n",
            "NEXT_PUBLIC_CONTRACT_ADDRESS=",
            vm.toString(tokenAddress),
            "\n",
            "NEXT_PUBLIC_USDC_ADDRESS=",
            vm.toString(usdcAddress),
            "\n",
            "NEXT_PUBLIC_RPC_URL=http://localhost:8545\n",
            "NEXT_PUBLIC_CHAIN_ID=31337\n"
        );
        vm.writeFile(frontendConfig, "deployments/.env.contract");

        console.log("\nConfig files generated:");
        console.log("  - deployments/latest.json");
        console.log("  - deployments/application-contract.yml");
        console.log("  - deployments/.env.contract");
    }
}
