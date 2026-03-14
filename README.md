# Polymarket Clone - 去中心化预测市场

## 📋 项目概述

一个完整的去中心化预测市场平台，包含：
- **智能合约**：Solidity + Foundry
- **后端**：Java Spring Boot + Redis + MySQL
- **前端**：Next.js 14 + Wagmi v2 + Viem
- **Relayer**：无 Gas 挂单 + 链上结算

## 🚀 快速开始

### 1. 环境要求

- Docker 20+
- Docker Compose V2+
- Foundry (forge, anvil)
- Node.js 18+
- JDK 17+

### 2. 一键启动

```bash
# 启动基础设施
./start_env.sh

# 部署合约（需要 Foundry）
forge script script/Deploy.s.sol --broadcast --rpc-url http://localhost:8545 --slow
```

### 3. 配置文件

部署后复制配置：
```bash
# Java 后端
cp deployments/application-contract.yml ../polymarket-core/src/main/resources/

# 前端
cp deployments/.env.contract ../polymarket-frontend/.env.local
```

## 📁 项目结构

```
polymarket-core/
├── src/                      # 智能合约
│   └── ConditionalToken.sol
├── script/                   # 部署脚本
│   ├── Deploy.s.sol
│   └── MockUSDC.sol
├── deployments/              # 部署配置（自动生成）
├── docker-compose.yml        # 基础设施编排
└── start_env.sh             # 一键启动脚本
```

## 🔧 服务端口

| 服务 | 端口 | 说明 |
|------|------|------|
| Redis | 6379 | K 线缓存 + Nonce 管理 |
| MySQL | 3306 | 订单持久化 |
| Anvil | 8545 | 本地以太坊节点 |
| Java 后端 | 8080 | 撮合引擎 |
| Next.js | 3000 | 前端界面 |

## ⚠️ 注意事项

1. **网络问题**：如遇到 Docker 镜像拉取超时，请配置镜像加速器
2. **Foundry 安装**：`curl -L https://foundry.paradigm.xyz | bash && foundryup`
3. **私钥安全**：Anvil 默认私钥仅用于测试，生产环境请使用独立私钥

## 📄 许可证

MIT
