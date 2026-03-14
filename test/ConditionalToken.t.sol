// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ConditionalToken.sol";
import "../script/MockUSDC.sol";

contract ConditionalTokenTest is Test {
    ConditionalToken public token;
    MockUSDC public usdc;
    
    address public alice = address(1);
    address public oracle = address(3);
    
    uint256 public marketId;
    uint256 constant SPLIT_AMOUNT = 100 * 10**6;
    
    function setUp() public {
        usdc = new MockUSDC();
        token = new ConditionalToken(address(usdc));
        
        usdc.faucet(alice, 10000 * 10**6);
        
        vm.prank(alice);
        usdc.approve(address(token), type(uint256).max);
        
        vm.prank(address(token));
        marketId = token.createCondition("Will it rain tomorrow?", oracle);
    }
    
    function test_CreateMarket() public {
        vm.prank(address(token));
        uint256 newMarketId = token.createCondition("New market?", oracle);
        
        (string memory question, address marketOracle, bool resolved, , uint256 createdAt, ) = token.markets(newMarketId);
        
        assertEq(keccak256(bytes(question)), keccak256(bytes("New market?")));
        assertEq(marketOracle, oracle);
        assertEq(resolved, false);
    }
    
    function test_SplitPosition() public {
        vm.prank(alice);
        token.splitPosition(marketId, SPLIT_AMOUNT);
        
        assertEq(token.balanceOf(alice, 1), SPLIT_AMOUNT);
        assertEq(token.balanceOf(alice, 2), SPLIT_AMOUNT);
    }
    
    function test_ResolveMarket_YesWins() public {
        vm.prank(alice);
        token.splitPosition(marketId, SPLIT_AMOUNT);
        
        uint256 balanceBefore = usdc.balanceOf(alice);
        
        vm.prank(oracle);
        token.resolveMarket(marketId, ConditionalToken.MarketState.YesWins);
        
        vm.prank(alice);
        token.redeemPositions(marketId, SPLIT_AMOUNT);
        
        assertEq(usdc.balanceOf(alice), balanceBefore + SPLIT_AMOUNT);
    }
    
    function test_ResolveMarket_NoWins() public {
        vm.prank(alice);
        token.splitPosition(marketId, SPLIT_AMOUNT);
        
        uint256 balanceBefore = usdc.balanceOf(alice);
        
        vm.prank(oracle);
        token.resolveMarket(marketId, ConditionalToken.MarketState.NoWins);
        
        vm.prank(alice);
        token.redeemPositions(marketId, SPLIT_AMOUNT);
        
        assertEq(usdc.balanceOf(alice), balanceBefore + SPLIT_AMOUNT);
    }
}
