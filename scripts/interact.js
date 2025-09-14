import hre from "hardhat";
const { ethers } = hre;

/**
 * 交互脚本 - 验证部署的合约功能
 * 这个脚本将展示如何与MetaNodeSwap系统交互，包括：
 * 1. 获取代币余额
 * 2. 添加流动性
 * 3. 执行代币交换
 * 4. 查看池子状态
 * 5. 收取交易手续费
 * 6. 移除流动性
 */

// 从部署脚本中复制的合约地址
const ADDRESSES = {
  TokenA: "0x0165878A594ca255338adfa4d48449f69242Eb8F",
  TokenB: "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853", 
  PoolManager: "0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6",
  PositionManager: "0x8A791620dd6260079BF849Dc5567aDC3F2FdC318",
  SwapRouter: "0x610178dA211FEF7D417bC0e6FeD39F05609AD788"
};

async function main() {
  // 获取账户
  const [deployer, user1, user2] = await ethers.getSigners();
  
  console.log("🔍 === MetaNodeSwap 交互演示 ===");
  console.log("部署者地址:", deployer.address);
  console.log("用户1地址:", user1.address);
  console.log("用户2地址:", user2.address);

  // 获取合约实例
  const tokenA = await ethers.getContractAt("TestToken", ADDRESSES.TokenA);
  const tokenB = await ethers.getContractAt("TestToken", ADDRESSES.TokenB);
  const poolManager = await ethers.getContractAt("PoolManager", ADDRESSES.PoolManager);
  const positionManager = await ethers.getContractAt("PositionManager", ADDRESSES.PositionManager);
  const swapRouter = await ethers.getContractAt("SwapRouter", ADDRESSES.SwapRouter);

  console.log("\n📊 === 第一步：查看初始状态 ===");
  
  // 查看代币余额
  const deployerBalanceA = await tokenA.balanceOf(deployer.address);
  const deployerBalanceB = await tokenB.balanceOf(deployer.address);
  
  console.log("部署者的代币余额:");
  console.log("- Token A:", ethers.formatEther(deployerBalanceA), "TKA");
  console.log("- Token B:", ethers.formatEther(deployerBalanceB), "TKB");

  // 查看池子状态
  const pools = await poolManager.getAllPools();
  console.log("池子数量:", pools.length);
  if (pools.length > 0) {
    console.log("池子当前流动性:", pools[0].liquidity.toString());
    console.log("池子当前价格(sqrt):", pools[0].sqrtPriceX96.toString());
  }

  console.log("\n💰 === 第二步：为用户分发测试代币 ===");
  
  // 给用户1和用户2分发代币进行测试
  const distributionAmount = ethers.parseEther("1000"); // 1000个代币
  
  await tokenA.mint(user1.address, distributionAmount);
  await tokenB.mint(user1.address, distributionAmount);
  await tokenA.mint(user2.address, distributionAmount);
  await tokenB.mint(user2.address, distributionAmount);
  
  console.log("✅ 已为用户1和用户2分发1000个TKA和1000个TKB");

  // 验证分发结果
  const user1BalanceA = await tokenA.balanceOf(user1.address);
  const user1BalanceB = await tokenB.balanceOf(user1.address);
  console.log("用户1余额: TKA =", ethers.formatEther(user1BalanceA), ", TKB =", ethers.formatEther(user1BalanceB));

  console.log("\n🏊 === 第三步：添加流动性 ===");
  
  // 用户1添加流动性
  const liquidityAmount0 = ethers.parseEther("100"); // 100个TokenA
  const liquidityAmount1 = ethers.parseEther("100"); // 100个TokenB
  
  // 授权PositionManager使用用户1的代币
  await tokenA.connect(user1).approve(ADDRESSES.PositionManager, liquidityAmount0);
  await tokenB.connect(user1).approve(ADDRESSES.PositionManager, liquidityAmount1);
  
  console.log("正在添加流动性: 100 TKA + 100 TKB...");
  
  // 构造添加流动性的参数
  const mintParams = {
    token0: ADDRESSES.TokenA,
    token1: ADDRESSES.TokenB,
    index: 0, // 池子索引
    amount0Desired: liquidityAmount0,
    amount1Desired: liquidityAmount1,
    recipient: user1.address,
    deadline: Math.floor(Date.now() / 1000) + 3600 // 1小时后过期
  };

  const mintTx = await positionManager.connect(user1).mint(mintParams);
  const mintReceipt = await mintTx.wait();
  
  console.log("✅ 流动性添加成功！交易哈希:", mintReceipt.hash);
  
  // 查看用户1的NFT
  const user1NFTBalance = await positionManager.balanceOf(user1.address);
  console.log("用户1持有的头寸NFT数量:", user1NFTBalance.toString());
  
  if (user1NFTBalance > 0) {
    // 获取第一个NFT的头寸信息
    const positionInfo = await positionManager.getPositionInfo(1);
    console.log("头寸信息:");
    console.log("- 所有者:", positionInfo.owner);
    console.log("- 流动性:", positionInfo.liquidity.toString());
    console.log("- 手续费率:", positionInfo.fee.toString(), "basis points");
  }

  console.log("\n🔄 === 第四步：执行代币交换 ===");
  
  // 用户2执行交换：用10个TokenA换取TokenB
  const swapAmountIn = ethers.parseEther("10");
  
  // 授权SwapRouter使用用户2的TokenA
  await tokenA.connect(user2).approve(ADDRESSES.SwapRouter, swapAmountIn);
  
  // 记录交换前的余额
  const beforeBalanceA = await tokenA.balanceOf(user2.address);
  const beforeBalanceB = await tokenB.balanceOf(user2.address);
  
  console.log("交换前用户2余额:");
  console.log("- Token A:", ethers.formatEther(beforeBalanceA), "TKA");  
  console.log("- Token B:", ethers.formatEther(beforeBalanceB), "TKB");
  
  // 构造交换参数
  const exactInputParams = {
    tokenIn: ADDRESSES.TokenA,
    tokenOut: ADDRESSES.TokenB,
    indexPath: [0], // 使用池子索引0
    recipient: user2.address,
    deadline: Math.floor(Date.now() / 1000) + 3600,
    amountIn: swapAmountIn,
    amountOutMinimum: 0, // 设为0用于测试（生产环境应设置合理的滑点保护）
    sqrtPriceLimitX96: "79228162514264337593543950300" // 略小于当前价格的限制
  };
  
  console.log("正在执行交换: 10 TKA -> TKB...");
  
  const swapTx = await swapRouter.connect(user2).exactInput(exactInputParams);
  const swapReceipt = await swapTx.wait();
  
  console.log("✅ 交换成功！交易哈希:", swapReceipt.hash);
  
  // 记录交换后的余额
  const afterBalanceA = await tokenA.balanceOf(user2.address);
  const afterBalanceB = await tokenB.balanceOf(user2.address);
  
  console.log("交换后用户2余额:");
  console.log("- Token A:", ethers.formatEther(afterBalanceA), "TKA");
  console.log("- Token B:", ethers.formatEther(afterBalanceB), "TKB");
  
  // 计算实际交换的数量
  const actualAmountIn = beforeBalanceA - afterBalanceA;
  const actualAmountOut = afterBalanceB - beforeBalanceB;
  
  console.log("实际交换结果:");
  console.log("- 输入:", ethers.formatEther(actualAmountIn), "TKA");
  console.log("- 输出:", ethers.formatEther(actualAmountOut), "TKB");
  console.log("- 交换比率:", (Number(ethers.formatEther(actualAmountOut)) / Number(ethers.formatEther(actualAmountIn))).toFixed(6));

  console.log("\n📈 === 第五步：查看更新后的池子状态 ===");
  
  // 查看池子的最新状态
  const updatedPools = await poolManager.getAllPools();
  if (updatedPools.length > 0) {
    const pool = updatedPools[0];
    console.log("池子最新状态:");
    console.log("- 当前流动性:", pool.liquidity.toString());
    console.log("- 当前价格(sqrt):", pool.sqrtPriceX96.toString());
    console.log("- 当前Tick:", pool.tick.toString());
  }

  console.log("\n💸 === 第六步：收取手续费 ===");
  
  // 检查用户1的头寸是否有可收取的手续费
  if (user1NFTBalance > 0) {
    console.log("正在收取头寸1的手续费...");
    
    // 记录收取手续费前的余额
    const beforeFeeBalanceA = await tokenA.balanceOf(user1.address);
    const beforeFeeBalanceB = await tokenB.balanceOf(user1.address);
    
    console.log("收取手续费前用户1余额:");
    console.log("- Token A:", ethers.formatEther(beforeFeeBalanceA), "TKA");
    console.log("- Token B:", ethers.formatEther(beforeFeeBalanceB), "TKB");
    
    // 调用收取手续费方法（只需要positionId和recipient两个参数）
    const collectTx = await positionManager.connect(user1).collect(1, user1.address);
    const collectReceipt = await collectTx.wait();
    
    console.log("✅ 手续费收取成功！交易哈希:", collectReceipt.hash);
    
    // 记录收取手续费后的余额
    const afterFeeBalanceA = await tokenA.balanceOf(user1.address);
    const afterFeeBalanceB = await tokenB.balanceOf(user1.address);
    
    console.log("收取手续费后用户1余额:");
    console.log("- Token A:", ethers.formatEther(afterFeeBalanceA), "TKA");
    console.log("- Token B:", ethers.formatEther(afterFeeBalanceB), "TKB");
    
    // 计算收取的手续费数量
    const feeAmountA = afterFeeBalanceA - beforeFeeBalanceA;
    const feeAmountB = afterFeeBalanceB - beforeFeeBalanceB;
    
    console.log("收取的手续费:");
    console.log("- Token A手续费:", ethers.formatEther(feeAmountA), "TKA");
    console.log("- Token B手续费:", ethers.formatEther(feeAmountB), "TKB");
  }

  console.log("\n❌ === 第七步：移除流动性（完全移除并销毁NFT）===");
  
  // 用户1移除全部流动性
  if (user1NFTBalance > 0) {
    // 获取当前头寸信息
    const currentPositionInfo = await positionManager.getPositionInfo(1);
    const currentLiquidity = currentPositionInfo.liquidity;
    
    console.log("当前头寸流动性:", currentLiquidity.toString());
    console.log("正在完全移除流动性并销毁头寸NFT...");
    
    // 记录移除前的余额
    const beforeRemoveBalanceA = await tokenA.balanceOf(user1.address);
    const beforeRemoveBalanceB = await tokenB.balanceOf(user1.address);
    
    console.log("移除前用户1余额:");
    console.log("- Token A:", ethers.formatEther(beforeRemoveBalanceA), "TKA");
    console.log("- Token B:", ethers.formatEther(beforeRemoveBalanceB), "TKB");
    
    // 调用burn方法完全移除流动性
    const burnTx = await positionManager.connect(user1).burn(1);
    const burnReceipt = await burnTx.wait();
    
    console.log("✅ 流动性移除成功！交易哈希:", burnReceipt.hash);
    
    // 记录移除后的余额
    const afterRemoveBalanceA = await tokenA.balanceOf(user1.address);
    const afterRemoveBalanceB = await tokenB.balanceOf(user1.address);
    
    console.log("移除后用户1余额:");
    console.log("- Token A:", ethers.formatEther(afterRemoveBalanceA), "TKA");
    console.log("- Token B:", ethers.formatEther(afterRemoveBalanceB), "TKB");
    
    // 计算实际移除的代币数量
    const removedAmountA = afterRemoveBalanceA - beforeRemoveBalanceA;
    const removedAmountB = afterRemoveBalanceB - beforeRemoveBalanceB;
    
    console.log("实际移除的代币:");
    console.log("- Token A:", ethers.formatEther(removedAmountA), "TKA");
    console.log("- Token B:", ethers.formatEther(removedAmountB), "TKB");
    
    // 检查NFT是否已被销毁
    const afterNFTBalance = await positionManager.balanceOf(user1.address);
    console.log("用户1剩余NFT数量:", afterNFTBalance.toString(), "(NFT已被销毁)");
  }

  console.log("\n🎉 === 演示完成！===");
  console.log("MetaNodeSwap系统运行正常，所有核心功能都工作正常！");
  console.log("\n本次演示包含了以下核心功能：");
  console.log("✅ 1. 代币分发和余额查询");
  console.log("✅ 2. 添加流动性（铸造头寸NFT）");
  console.log("✅ 3. 执行代币交换");
  console.log("✅ 4. 收取交易手续费");
  console.log("✅ 5. 移除流动性");
  console.log("\n你可以继续探索：");
  console.log("1. 尝试不同数量的交换");
  console.log("2. 添加更多流动性");
  console.log("3. 创建新的交易池");
  console.log("4. 完全移除头寸（燃烧NFT）");
}

// 执行交互脚本
main()
  .then(() => {
    console.log("\n✅ 交互演示完成");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ 交互演示失败:");
    console.error(error);
    process.exit(1);
  });