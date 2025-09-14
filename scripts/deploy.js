import hre from "hardhat";
const { ethers } = hre;

/**
 * 主部署函数
 * 部署完整的MetaNodeSwap系统，包括：
 * 1. 两个测试代币（Token A和Token B）
 * 2. PoolManager（池管理合约，继承自Factory）
 * 3. PositionManager（头寸管理合约，ERC721 NFT）
 * 4. SwapRouter（交易路由合约）
 * 5. 创建一个测试池并初始化价格
 */
async function main() {
  // 获取部署账户
  const [deployer] = await ethers.getSigners();

  console.log("使用账户部署合约:", deployer.address);
  console.log("账户余额:", (await deployer.provider.getBalance(deployer.address)).toString());

  // 第一步：部署测试代币
  console.log("\n=== 第一步：部署测试代币 ===");
  const TestToken = await ethers.getContractFactory("TestToken");
  
  // 部署第一个测试代币：Token A
  const token0 = await TestToken.deploy("Token A", "TKA", 1000000);
  await token0.waitForDeployment();
  console.log("Token A 部署地址:", await token0.getAddress());

  // 部署第二个测试代币：Token B
  const token1 = await TestToken.deploy("Token B", "TKB", 1000000);
  await token1.waitForDeployment();
  console.log("Token B 部署地址:", await token1.getAddress());

  // 确保 token0 地址 < token1 地址（Uniswap标准）
  // 这样可以确保在所有地方都按相同顺序处理这两个代币
  let tokenA, tokenB;
  const token0Address = await token0.getAddress();
  const token1Address = await token1.getAddress();
  
  if (token0Address.toLowerCase() < token1Address.toLowerCase()) {
    tokenA = token0;
    tokenB = token1;
  } else {
    tokenA = token1;
    tokenB = token0;
  }
  console.log("标准化后的代币顺序:");
  console.log("- TokenA (token0):", await tokenA.getAddress());
  console.log("- TokenB (token1):", await tokenB.getAddress());

  // 第二步：部署核心合约系统
  console.log("\n=== 第二步：部署核心合约系统 ===");
  
  // 部署 PoolManager（池管理合约）
  // 这个合约继承自Factory，负责创建和管理所有交易池
  const PoolManager = await ethers.getContractFactory("PoolManager");
  const poolManager = await PoolManager.deploy();
  await poolManager.waitForDeployment();
  console.log("PoolManager 部署地址:", await poolManager.getAddress());

  // 部署 PositionManager（头寸管理合约）
  // 这是一个ERC721合约，将流动性头寸表示为NFT
  const PositionManager = await ethers.getContractFactory("PositionManager");
  const positionManager = await PositionManager.deploy(await poolManager.getAddress());
  await positionManager.waitForDeployment();
  console.log("PositionManager 部署地址:", await positionManager.getAddress());

  // 部署 SwapRouter（交易路由合约）
  // 负责处理代币交换，支持多池路径交易
  const SwapRouter = await ethers.getContractFactory("SwapRouter");
  const swapRouter = await SwapRouter.deploy(await poolManager.getAddress());
  await swapRouter.waitForDeployment();
  console.log("SwapRouter 部署地址:", await swapRouter.getAddress());

  // 第三步：创建测试池
  console.log("\n=== 第三步：创建并初始化测试池 ===");
  
  // 设置初始价格为1:1（即1个TokenA = 1个TokenB）
  // sqrtPriceX96 = sqrt(price) * 2^96
  // 对于1:1的价格比率：sqrt(1) * 2^96 = 2^96
  const sqrtPriceX96 = ethers.parseUnits("79228162514264337593543950336", 0); // sqrt(1) * 2^96
  console.log("设置初始价格比率: 1:1");
  console.log("sqrtPriceX96:", sqrtPriceX96.toString());
  
  // 构造创建池子的参数
  const createParams = {
    token0: await tokenA.getAddress(),        // 第一个代币地址
    token1: await tokenB.getAddress(),        // 第二个代币地址
    fee: 3000,                     // 手续费率：3000 = 0.3%
    tickLower: -887220,            // 价格区间下限（接近最小值，支持全价格范围）
    tickUpper: 887220,             // 价格区间上限（接近最大值，支持全价格范围）
    sqrtPriceX96: sqrtPriceX96     // 初始价格
  };

  console.log("创建池子参数:");
  console.log("- Token0:", createParams.token0);
  console.log("- Token1:", createParams.token1);
  console.log("- 手续费率:", createParams.fee / 10000, "%");
  console.log("- Tick范围: [", createParams.tickLower, ",", createParams.tickUpper, "]");

  // 调用合约创建并初始化池子
  const tx = await poolManager.createAndInitializePoolIfNecessary(createParams);
  await tx.wait();
  console.log("✅ 测试池创建和初始化完成");

  // 第四步：验证部署结果
  console.log("\n=== 第四步：验证部署结果 ===");
  
  // 获取并显示池信息
  const pools = await poolManager.getAllPools();
  if (pools.length > 0) {
    console.log("池子信息验证:");
    console.log("- Token0地址:", pools[0].token0);
    console.log("- Token1地址:", pools[0].token1);
    console.log("- 手续费率:", pools[0].fee.toString(), "basis points");
    console.log("- 当前Tick:", pools[0].tick.toString());
    console.log("- 当前流动性:", pools[0].liquidity.toString());
    console.log("- 当前价格(sqrt):", pools[0].sqrtPriceX96.toString());
  }

  // 获取交易对信息
  const pairs = await poolManager.getPairs();
  console.log("交易对数量:", pairs.length);

  // 最终部署总结
  console.log("\n🎉 === 部署完成！系统已就绪 ===");
  console.log("\n📋 合约地址汇总:");
  console.log("┌─────────────────────┬─────────────────────────────────────────────┐");
  console.log("│ 合约名称            │ 地址                                        │");
  console.log("├─────────────────────┼─────────────────────────────────────────────┤");
  console.log(`│ Token A (TKA)       │ ${await tokenA.getAddress()} │`);
  console.log(`│ Token B (TKB)       │ ${await tokenB.getAddress()} │`);
  console.log(`│ PoolManager         │ ${await poolManager.getAddress()} │`);
  console.log(`│ PositionManager     │ ${await positionManager.getAddress()} │`);
  console.log(`│ SwapRouter          │ ${await swapRouter.getAddress()} │`);
  console.log("└─────────────────────┴─────────────────────────────────────────────┘");

  console.log("\n🔧 接下来你可以：");
  console.log("1. 使用 PositionManager 添加流动性");
  console.log("2. 使用 SwapRouter 执行代币交换");
  console.log("3. 查看 PoolManager 获取池子信息");
  console.log("4. 运行测试：npm run test");
}

// 执行部署脚本
main()
  .then(() => {
    console.log("\n✅ 部署脚本执行成功");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ 部署脚本执行失败:");
    console.error(error);
    process.exit(1);
  });