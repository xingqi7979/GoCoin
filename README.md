# MetaNodeSwap - 去中心化交易所

MetaNodeSwap 是一个基于以太坊的去中心化交易所（DEX），采用集中流动性模型，类似于 Uniswap V3。每个交易池都有固定的价格范围，所有交易只能在此价格范围内进行。

## 🏗️ 系统架构

### 合约结构
系统按照自顶向下的方式设计，包含以下核心合约：

```
MetaNodeSwap 系统架构
├── 顶层合约（面向用户）
│   ├── PoolManager.sol     - 池管理合约，对应 Pool 页面
│   ├── PositionManager.sol - 头寸管理合约，对应 Position 页面  
│   └── SwapRouter.sol      - 交易路由合约，对应 Swap 页面
├── 底层合约（核心逻辑）
│   ├── Factory.sol         - 池工厂合约
│   └── Pool.sol           - 单个交易池合约
└── 工具库
    ├── Math.sol           - 数学计算库
    └── TickMath.sol       - Tick价格转换库
```

## 📋 功能特性

### 🏊‍♂️ 流动性管理
- ✅ **池创建**：任何人都可以创建交易池，指定价格范围和手续费
- ✅ **流动性添加**：流动性提供者可以在指定价格范围内添加流动性
- ✅ **流动性移除**：可以部分或完全移除之前添加的流动性
- ✅ **手续费收取**：按流动性贡献比例自动分配交易手续费

### 💱 交易功能
- ✅ **精确输入交易**：指定输入代币数量，最大化输出
- ✅ **精确输出交易**：指定输出代币数量，最小化输入
- ✅ **多池路径**：支持通过多个池子进行复杂交易
- ✅ **滑点保护**：设置最小输出/最大输入保护

### 🎯 NFT 头寸
- ✅ **ERC721 标准**：每个流动性头寸都是一个 NFT
- ✅ **头寸管理**：查看、转移、销毁流动性头寸
- ✅ **手续费收取**：通过 NFT 管理收取的手续费

## 🛠️ 技术栈

- **智能合约**：Solidity ^0.8.19
- **开发框架**：Hardhat
- **标准库**：OpenZeppelin Contracts
- **测试框架**：Mocha + Chai
- **代码规范**：完整的中文注释

## 🚀 快速开始

### 环境要求
- Node.js >= 16.0.0
- npm >= 8.0.0

### 安装依赖
```bash
npm install
```

### 编译合约
```bash
npm run compile
```

### 运行测试
```bash
npm run test
```

### 本地部署
```bash
# 启动本地节点
npm run node

# 在新终端中部署到本地网络
npm run deploy:localhost
```

## 📁 项目结构

```
MetaNodeCoin/
├── contracts/                 # 智能合约源码
│   ├── interfaces/            # 合约接口定义
│   │   ├── IFactory.sol      # 工厂合约接口
│   │   ├── IPool.sol         # 池合约接口
│   │   └── ICallback.sol     # 回调接口
│   ├── libraries/            # 工具库
│   │   ├── Math.sol          # 数学计算库
│   │   └── TickMath.sol      # Tick价格转换
│   ├── Factory.sol           # 池工厂合约
│   ├── Pool.sol              # 单个交易池
│   ├── PoolManager.sol       # 池管理合约
│   ├── PositionManager.sol   # 头寸管理合约
│   ├── SwapRouter.sol        # 交易路由合约
│   └── TestToken.sol         # 测试代币合约
├── scripts/                  # 部署脚本
│   └── deploy.js            # 主部署脚本
├── test/                     # 测试文件
│   └── MetaNodeSwap.test.js # 主测试套件
├── hardhat.config.js        # Hardhat配置
└── package.json             # 项目配置
```

## 🔧 使用指南

### 1. 创建交易池

```javascript
// 通过 PoolManager 创建新池
const createParams = {
  token0: tokenA.address,     // 第一个代币地址
  token1: tokenB.address,     // 第二个代币地址
  fee: 3000,                  // 0.3% 手续费
  tickLower: -887220,         // 价格区间下限
  tickUpper: 887220,          // 价格区间上限
  sqrtPriceX96: "79228162514264337593543950336"  // 初始价格 1:1
};

await poolManager.createAndInitializePoolIfNecessary(createParams);
```

### 2. 添加流动性

```javascript
// 通过 PositionManager 添加流动性
const mintParams = {
  token0: tokenA.address,
  token1: tokenB.address,
  index: 0,                   // 池子索引
  amount0Desired: ethers.utils.parseEther("100"),
  amount1Desired: ethers.utils.parseEther("100"),
  recipient: userAddress,
  deadline: Math.floor(Date.now() / 1000) + 3600
};

await positionManager.mint(mintParams);
```

### 3. 执行交易

```javascript
// 通过 SwapRouter 进行代币交换
const exactInputParams = {
  tokenIn: tokenA.address,
  tokenOut: tokenB.address,
  indexPath: [0],             // 使用的池子索引路径
  recipient: userAddress,
  deadline: Math.floor(Date.now() / 1000) + 3600,
  amountIn: ethers.utils.parseEther("10"),
  amountOutMinimum: 0,
  sqrtPriceLimitX96: "4295128740"
};

await swapRouter.exactInput(exactInputParams);
```

## 📊 核心概念

### Tick 和价格
- **Tick**：价格的对数表示，用于高效计算
- **sqrtPriceX96**：价格平方根的固定点表示（Q64.96 格式）
- **价格范围**：每个池子都有固定的 [tickLower, tickUpper] 范围

### 流动性计算
- **集中流动性**：流动性集中在指定价格范围内
- **手续费分配**：按流动性贡献比例分配交易手续费
- **无常损失**：价格波动可能导致的资产价值变化

### 交易机制
- **恒定乘积**：在价格范围内维持 x * y = k 公式
- **滑点控制**：通过最小输出/最大输入参数控制
- **多池路由**：支持跨多个池子的复杂交易路径

## 🧪 测试覆盖

项目包含完整的测试套件，覆盖以下功能：

- ✅ **池创建测试**：验证池的创建和初始化
- ✅ **流动性管理测试**：验证流动性的添加、移除和查询
- ✅ **交易功能测试**：验证精确输入/输出交易
- ✅ **NFT 头寸测试**：验证头寸 NFT 的铸造和管理
- ✅ **异常处理测试**：验证各种边界条件和错误处理

运行测试查看详细结果：
```bash
npm run test
```

## 🔒 安全考虑

### 已实现的安全措施
- ✅ **重入攻击保护**：使用 lock 修饰器防止重入
- ✅ **整数溢出保护**：使用 Solidity ^0.8.19 内置检查
- ✅ **授权检查**：严格的权限控制和所有权验证
- ✅ **滑点保护**：支持最小输出/最大输入限制
- ✅ **时间锁保护**：支持交易截止时间设置

### 注意事项
⚠️ **测试环境**：当前版本仅用于测试和学习目的
⚠️ **审计需求**：生产环境使用前需要进行专业安全审计
⚠️ **价格风险**：集中流动性可能增加无常损失风险

## 🤝 贡献指南

欢迎提交问题报告和功能请求！

1. Fork 本项目
2. 创建功能分支：`git checkout -b feature-name`
3. 提交更改：`git commit -m 'Add feature'`
4. 推送分支：`git push origin feature-name`
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [Uniswap V3](https://github.com/Uniswap/v3-core) - 设计灵感来源
- [OpenZeppelin](https://openzeppelin.com/) - 安全的合约标准库
- [Hardhat](https://hardhat.org/) - 出色的开发工具链

---

**免责声明**：此项目仅用于教育和研究目的。在生产环境中使用前，请确保进行充分的测试和安全审计。

## 本地测试
MetaNodeSwap DEX系统现在可以在本地环境中完全正常运行：
  1. 启动本地网络：npx hardhat node
  2. 部署合约：npx hardhat run scripts/deploy.js --network localhost
  3. 交互测试：npx hardhat run scripts/interact.js --network localhost
  4. 运行测试：npm test

  所有功能都已通过验证，系统具备完整的DEX功能，包括流动性管理、代币交换、NFT头寸管理等。用户现在可以基于这个系统进行
  进一步的开发和测试。