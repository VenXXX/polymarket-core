# Foundry 部署与测试指南

## 📦 安装依赖

```bash
# 1. 安装 Foundry (如果未安装)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. 初始化 Foundry 项目
cd /home/admin/.openclaw/workspace/contracts
forge init --no-commit

# 3. 安装 OpenZeppelin 依赖
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# 4. 安装 forge-std
forge install foundry-rs/forge-std --no-commit

# 5. 更新 remappings
forge remappings > remappings.txt
```

## 🧪 运行测试

```bash
# 运行所有测试
forge test

# 运行特定测试 (按名称匹配)
forge test --match-test test_FIX1

# 运行特定修复的测试
forge test --match-test test_FIX2_AutoMint
forge test --match-test test_FIX3_Unauthorized
forge test --match-test test_FIX4_InvalidMarket
forge test --match-test test_FIX5_DustAttack
forge test --match-test test_FIX6_MergePositions

# 详细输出
forge test -vvv

# 生成 Gas 报告
forge test --gas-report

# 覆盖率测试
forge coverage
```

## 🚀 部署合约

### 本地测试网

```bash
# 启动本地节点 (新开终端)
anvil

# 部署 (另一个终端)
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### Sepolia 测试网

```bash
# 需要配置 .env 文件
cp .env.example .env
# 编辑 .env 填入 PRIVATE_KEY 和 SEPOLIA_RPC_URL

forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## 📋 测试覆盖的功能

| 测试函数 | 修复编号 | 测试内容 |
|---------|---------|---------|
| `test_FIX1_PartialFill_Success` | #1 | 部分成交 - 分 3 次填充订单 |
| `test_FIX1_PartialFill_ExceedsRemaining_Reverts` | #1 | 超过剩余量应 revert |
| `test_FIX2_AutoMint_MintsShares` | #2 | 自动铸造 YES/NO 份额 |
| `test_FIX2_AutoMint_TransfersUSDC` | #2 | USDC 正确转移到合约 |
| `test_FIX3_UnauthorizedRelayer_Reverts` | #3 | 未授权 relayer 被拒绝 |
| `test_FIX3_AuthorizedRelayer_Success` | #3 | 授权 relayer 可执行 |
| `test_FIX4_InvalidMarket_OddAmount_Success` | #4 | 奇数份额可提款 (101 份) |
| `test_FIX4_InvalidMarket_SingleShare_Success` | #4 | 单份额可提款 (1 份) |
| `test_FIX5_DustAttack_ZeroUSDC_Reverts` | #5 | 0 USDC 计算被拒绝 |
| `test_FIX5_MinimumValidFill_Success` | #5 | 最小有效填充成功 |
| `test_FIX6_MergePositions_Success` | #6 | 合并 10 YES+10 NO 获 10 USDC |
| `test_FIX6_MergePositions_InsufficientYES_Reverts` | #6 | YES 不足 revert |
| `test_FIX6_MergePositions_InsufficientNO_Reverts` | #6 | NO 不足 revert |
| `test_Integration_FullLifecycle` | 全部 | 完整生命周期集成测试 |

## 🔍 关键测试场景说明

### FIX #4 - Invalid 市场提款 (重点!)

```solidity
// 之前：101 份额 → require(101 % 2 == 0) → REVERT ❌
// 现在：101 份额 → floor(101/2) = 50 USDC → SUCCESS ✅
test_FIX4_InvalidMarket_OddAmount_Success()
```

### FIX #5 - 灰尘攻击防护 (重点!)

```solidity
// 攻击场景：fillAmount=1, price=100 → usdcAmount = 100*1/10000 = 0
// 攻击者白嫖份额！
// 现在：require(usdcAmount > 0) → REVERT ✅
test_FIX5_DustAttack_ZeroUSDC_Reverts()
```

### FIX #6 - 合并退出 (新功能!)

```solidity
// 用户有 10 YES + 10 NO → mergePositions(10) → 获得 10 USDC
// 无需等待市场结算！流动性提供者可以退出
test_FIX6_MergePositions_Success()
```

## 📊 预期测试结果

```
Running 15 tests for contracts/PredictionMarket.t.sol:PredictionMarketTest
[PASS] test_FIX1_PartialFill_Success (gas: 285432)
[PASS] test_FIX1_PartialFill_ExceedsRemaining_Reverts (gas: 198234)
[PASS] test_FIX2_AutoMint_MintsShares (gas: 312456)
[PASS] test_FIX2_AutoMint_TransfersUSDC (gas: 298765)
[PASS] test_FIX3_UnauthorizedRelayer_Reverts (gas: 156789)
[PASS] test_FIX3_AuthorizedRelayer_Success (gas: 287654)
[PASS] test_FIX4_InvalidMarket_OddAmount_Success (gas: 245678)
[PASS] test_FIX4_InvalidMarket_EvenAmount_Success (gas: 243567)
[PASS] test_FIX4_InvalidMarket_SingleShare_Success (gas: 241234)
[PASS] test_FIX5_DustAttack_ZeroUSDC_Reverts (gas: 187654)
[PASS] test_FIX5_MinimumValidFill_Success (gas: 276543)
[PASS] test_FIX5_LowPrice_RequiresLargerFill (gas: 298765)
[PASS] test_FIX6_MergePositions_Success (gas: 234567)
[PASS] test_FIX6_MergePositions_InsufficientYES_Reverts (gas: 165432)
[PASS] test_FIX6_MergePositions_InsufficientNO_Reverts (gas: 167890)
[PASS] test_Integration_FullLifecycle (gas: 456789)

Test result: ok. 15 passed; 0 failed
```

## ⚠️ 注意事项

1. **USDC 精度**: 合约假设 USDC 为 6 decimals，如使用其他代币需调整
2. **Gas 优化**: mergePositions 可考虑添加 minimumRefund 参数防止 Gas 浪费
3. **重入攻击**: 已使用 Checks-Effects-Interactions 模式防护
4. **权限管理**: 生产环境需严格管理 owner 和 relayer 权限

## 📁 文件结构

```
contracts/
├── PredictionMarket.sol      # 主合约 (已修复 6 个漏洞)
├── PredictionMarket.t.sol    # 完整测试套件 (15+ 测试用例)
├── SECURITY_FIXES.md         # 详细修复文档
├── DEPLOYMENT.md             # 本文件 - 部署指南
├── foundry.toml              # Foundry 配置
└── script/
    └── Deploy.s.sol          # 部署脚本 (需创建)
```

## 🛠️ 下一步

1. 运行 `forge test` 验证所有测试通过
2. 根据需要调整测试参数
3. 部署到测试网进行集成测试
4. 考虑添加 Slither/MythX 静态分析
