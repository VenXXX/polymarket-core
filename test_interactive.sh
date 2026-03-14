#!/bin/bash
# Polymarket 合约交互式测试脚本

CONTRACT="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
USDC="0x5FbDB2315678afecb367f032d93F642f64180aa3"
RPC="http://localhost:8545"
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ACCOUNT="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

echo "============================================"
echo "  Polymarket 合约交互式测试"
echo "============================================"
echo ""
echo "合约地址:"
echo "  ConditionalToken: $CONTRACT"
echo "  MockUSDC:         $USDC"
echo "  RPC:              $RPC"
echo "  账户：$ACCOUNT"
echo ""

# 1. 检查 USDC 余额
echo "[1] 检查 USDC 余额..."
cast call $USDC "balanceOf(address)(uint256)" $ACCOUNT --rpc-url $RPC
echo ""

# 2. 授权合约花费 USDC
echo "[2] 授权合约花费 USDC..."
cast send $USDC "approve(address,uint256)" $CONTRACT $(cast max-uint) --private-key $PRIVATE_KEY --rpc-url $RPC
echo ""

# 3. 创建市场
echo "[3] 创建市场..."
cast send $CONTRACT "createCondition(string,address)" "Will ETH reach $5000 by EOY?" $ACCOUNT --private-key $PRIVATE_KEY --rpc-url $RPC
echo ""

# 4. 查看市场信息
echo "[4] 查看市场 #0..."
cast call $CONTRACT "markets(uint256)(string,address,bool,uint8,uint256,uint256)" 0 --rpc-url $RPC
echo ""

# 5. 拆分仓位
echo "[5] 拆分仓位 (100 USDC)..."
cast send $CONTRACT "splitPosition(uint256,uint256)" 0 100000000 --private-key $PRIVATE_KEY --rpc-url $RPC
echo ""

# 6. 查看 ERC1155 余额
echo "[6] 查看 YES 代币余额 (tokenId=1)..."
cast call $CONTRACT "balanceOf(address,uint256)(uint256)" $ACCOUNT 1 --rpc-url $RPC
echo ""

echo "============================================"
echo "  测试完成！"
echo "============================================"
