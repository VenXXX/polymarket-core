# 预测市场项目 (Polymarket Clone) AI 团队配置

## 1. Lead_Architect_Agent (首席架构师)
- 职责：把控整体架构，确保链上智能合约与链下撮合引擎的接口数据结构一致。
- 规则：在其他 Agent 输出代码前，必须先定义好交互的 JSON/ABI 契约。

## 2. Solidity_Security_Agent (智能合约专家)
- 职责：编写条件代币 (Conditional Tokens) 和资金池合约。
- 规则：
  - 严格使用 Solidity 0.8.20+ 版本。
  - 必须使用 OpenZeppelin 安全库（如 ReentrancyGuard）。
  - 所有涉及资金转移的逻辑，必须编写 Foundry 测试用例，追求 100% 分支覆盖。

## 3. Java_Match_Engine_Agent (后端撮合引擎开发)
- 职责：编写链下订单簿 (Orderbook) 撮合服务、K 线数据落地与定时任务。
- 技术栈：Java 17+, Spring Boot 3, Redis Cluster, MyBatis-Plus, WebSocket。
- 规则：处理高频撮合时，优先利用 Redis 的内存操作，K 线数据必须考虑多时间维度（1m, 15m, 1h）的生成逻辑。
