# GuardianStopLoss
---
Sepolia address:
  - 逻辑合约: 0x6C887209E2c8CcC6d85d5AdC889e41187eC247a2
  - 代理合约: 0xc1db291dB309AA66f0074006DC0b50db8ba4881F
  - SwapRouter: 0xEb8dF084Fc5F8423c3085d108fbe3E0532edc8b7
---

一个双预言机喂价的去中心化 ETH 止损保护系统。用户可以存入 ETH 并设置止损价格。当 ETH 价格跌破阈值时，keeper 可以执行订单，将 ETH 交换为 USDC 并获得赏金。

## 功能特性

- **止损保护**：当价格跌破用户设定的止损线时，自动将 ETH 兑换为 USDC。
- **Keeper 激励机制**：Keeper 执行有效止损订单可获得一定比例的赏金。
- **双预言机安全机制**：
  - 主预言机：Chainlink 数据喂价（价格 < 止损价触发）。
  - 辅预言机（交叉验证）：Uniswap V3 TWAP（时间加权平均价格）防止闪电贷攻击或预言机操控。
- **可升级性**：
  - 采用 UUPS 代理升级标准以支持未来迭代。
  - 包含 `uint256[50] private __gap` 以防止升级期间的存储冲突。
- **紧急暂停**：Owner 可在紧急情况下暂停合约。

## 架构说明

- `GuardianStopLoss.sol`：主合约，负责管理存款、订单与执行逻辑。
- `OracleLibrary.sol`：用于 Uniswap V3 TWAP 计算的辅助库。
- `FullMath.sol` & `TickMath.sol`：Uniswap V3 计算使用的数学库。

## 部署方式

### 安装依赖

```bash
forge install
```

### 编译

```bash
forge build
```

### 测试
测试基于主网分叉环境运行，以便与真实的 Uniswap V3 池和 Chainlink 喂价交互。
```bash
forge test
```

### 部署

```bash
make deploy-sepolia
```

或手动部署：
```bash
source .env
forge script script/Deploy.s.sol:DeployScript --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
```
