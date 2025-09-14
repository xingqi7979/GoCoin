import { expect } from "chai";
import hre from "hardhat";
const { ethers } = hre;

/**
 * MetaNodeSwap 完整测试套件
 * 测试整个去中心化交易所系统的核心功能，包括：
 * 1. 池创建和管理
 * 2. 流动性添加和移除
 * 3. 代币交换功能
 * 4. NFT头寸管理
 */
describe("MetaNodeSwap", function () {
  // 全局测试变量
  let poolManager, positionManager, swapRouter;  // 核心合约实例
  let tokenA, tokenB;                            // 测试代币实例
  let owner, addr1, addr2;                       // 测试账户
  let poolAddress;                               // 池子地址

  /**
   * 每个测试用例执行前的初始化
   * 部署所有必要的合约并进行基础设置
   */
  beforeEach(async function () {
    // 获取测试账户
    [owner, addr1, addr2] = await ethers.getSigners();

    // === 第一步：部署测试代币 ===
    const TestToken = await ethers.getContractFactory("TestToken");
    
    // 创建两个测试代币，每个初始供应量100万
    const token0 = await TestToken.deploy("Token A", "TKA", 1000000);
    const token1 = await TestToken.deploy("Token B", "TKB", 1000000);
    
    await token0.waitForDeployment();
    await token1.waitForDeployment();

    // 确保代币地址按标准顺序排列（token0 < token1）
    // 这是Uniswap的标准做法，确保一致性
    const token0Address = await token0.getAddress();
    const token1Address = await token1.getAddress();
    
    if (token0Address.toLowerCase() < token1Address.toLowerCase()) {
      tokenA = token0;
      tokenB = token1;
    } else {
      tokenA = token1;
      tokenB = token0;
    }

    // === 第二步：部署核心合约系统 ===
    
    // 部署池管理合约（继承自Factory）
    const PoolManager = await ethers.getContractFactory("PoolManager");
    poolManager = await PoolManager.deploy();
    await poolManager.waitForDeployment();

    // 部署头寸管理合约（ERC721 NFT）
    const PositionManager = await ethers.getContractFactory("PositionManager");
    positionManager = await PositionManager.deploy(await poolManager.getAddress());
    await positionManager.waitForDeployment();

    // 部署交易路由合约
    const SwapRouter = await ethers.getContractFactory("SwapRouter");
    swapRouter = await SwapRouter.deploy(await poolManager.getAddress());
    await swapRouter.waitForDeployment();

    // === 第三步：为测试账户分发代币 ===
    
    // 给addr1账户铸造10,000个代币用于测试
    await tokenA.mint(addr1.address, ethers.parseEther("10000"));
    await tokenB.mint(addr1.address, ethers.parseEther("10000"));
    
    // 给addr2账户铸造10,000个代币用于测试
    await tokenA.mint(addr2.address, ethers.parseEther("10000"));
    await tokenB.mint(addr2.address, ethers.parseEther("10000"));
  });

  /**
   * 测试组1：池创建功能
   * 验证交易池的创建、初始化和查询功能
   */
  describe("池创建", function () {
    /**
     * 测试用例：应该能创建并初始化池
     */
    it("应该能创建并初始化池", async function () {
      // 设置初始价格为1:1比率
      // sqrtPriceX96 = sqrt(1) * 2^96
      const sqrtPriceX96 = ethers.parseUnits("79228162514264337593543950336", 0);
      
      // 构造池创建参数
      const createParams = {
        token0: await tokenA.getAddress(),        // 第一个代币
        token1: await tokenB.getAddress(),        // 第二个代币
        fee: 3000,                     // 0.3% 手续费
        tickLower: -887220,            // 支持全价格范围的下限
        tickUpper: 887220,             // 支持全价格范围的上限
        sqrtPriceX96: sqrtPriceX96     // 初始价格
      };

      // 执行池创建
      await poolManager.createAndInitializePoolIfNecessary(createParams);
      
      // 验证池创建结果
      const pools = await poolManager.getAllPools();
      expect(pools.length).to.equal(1);                    // 应该有1个池
      expect(pools[0].token0).to.equal(await tokenA.getAddress());    // 验证token0地址
      expect(pools[0].token1).to.equal(await tokenB.getAddress());    // 验证token1地址
    });

    /**
     * 测试用例：应该能获取交易对信息
     */
    it("应该能获取交易对信息", async function () {
      // 设置测试参数并创建池
      const sqrtPriceX96 = ethers.parseUnits("79228162514264337593543950336", 0);
      
      const createParams = {
        token0: await tokenA.getAddress(),
        token1: await tokenB.getAddress(),
        fee: 3000,
        tickLower: -887220,
        tickUpper: 887220,
        sqrtPriceX96: sqrtPriceX96
      };

      await poolManager.createAndInitializePoolIfNecessary(createParams);
      
      // 验证交易对信息
      const pairs = await poolManager.getPairs();
      expect(pairs.length).to.equal(1);                    // 应该有1个交易对
      expect(pairs[0].token0).to.equal(await tokenA.getAddress());    // 验证token0
      expect(pairs[0].token1).to.equal(await tokenB.getAddress());    // 验证token1
    });
  });

  /**
   * 测试组2：流动性管理
   * 验证流动性的添加、查询和管理功能
   */
  describe("流动性管理", function () {
    /**
     * 每个流动性测试前的准备工作
     * 创建一个基础的交易池
     */
    beforeEach(async function () {
      // 创建测试池
      const sqrtPriceX96 = ethers.parseUnits("79228162514264337593543950336", 0);
      
      const createParams = {
        token0: await tokenA.getAddress(),
        token1: await tokenB.getAddress(),
        fee: 3000,
        tickLower: -887220,
        tickUpper: 887220,
        sqrtPriceX96: sqrtPriceX96
      };

      await poolManager.createAndInitializePoolIfNecessary(createParams);
      // 获取池地址供后续测试使用
      poolAddress = await poolManager.getPoolAddress(0);
    });

    /**
     * 测试用例：应该能添加流动性
     */
    it("应该能添加流动性", async function () {
      // 设置要添加的流动性数量
      const amount0 = ethers.parseEther("100");  // 100个TokenA
      const amount1 = ethers.parseEther("100");  // 100个TokenB

      // 授权PositionManager使用用户的代币
      await tokenA.connect(addr1).approve(await positionManager.getAddress(), amount0);
      await tokenB.connect(addr1).approve(await positionManager.getAddress(), amount1);

      // 构造添加流动性的参数
      const mintParams = {
        token0: await tokenA.getAddress(),                           // 第一个代币
        token1: await tokenB.getAddress(),                           // 第二个代币
        index: 0,                                         // 池子索引
        amount0Desired: amount0,                          // 期望的token0数量
        amount1Desired: amount1,                          // 期望的token1数量
        recipient: addr1.address,                         // NFT接收者
        deadline: Math.floor(Date.now() / 1000) + 3600    // 1小时后过期
      };

      // 执行添加流动性操作
      const tx = await positionManager.connect(addr1).mint(mintParams);
      const receipt = await tx.wait();
      
      // 验证交易成功
      expect(receipt.status).to.equal(1);
      
      // 验证NFT已铸造给用户
      expect(await positionManager.balanceOf(addr1.address)).to.equal(1);
    });

    /**
     * 测试用例：应该能获取头寸信息
     */
    it("应该能获取头寸信息", async function () {
      // 添加流动性（与上个测试相同的步骤）
      const amount0 = ethers.parseEther("100");
      const amount1 = ethers.parseEther("100");

      await tokenA.connect(addr1).approve(await positionManager.getAddress(), amount0);
      await tokenB.connect(addr1).approve(await positionManager.getAddress(), amount1);

      const mintParams = {
        token0: await tokenA.getAddress(),
        token1: await tokenB.getAddress(),
        index: 0,
        amount0Desired: amount0,
        amount1Desired: amount1,
        recipient: addr1.address,
        deadline: Math.floor(Date.now() / 1000) + 3600
      };

      await positionManager.connect(addr1).mint(mintParams);
      
      // 验证头寸信息
      const positionInfo = await positionManager.getPositionInfo(1);
      expect(positionInfo.owner).to.equal(addr1.address);      // 验证所有者
      expect(positionInfo.token0).to.equal(await tokenA.getAddress());    // 验证token0
      expect(positionInfo.token1).to.equal(await tokenB.getAddress());    // 验证token1
    });
  });

  /**
   * 测试组3：交易功能
   * 验证代币交换的核心功能
   */
  describe("交易功能", function () {
    /**
     * 每个交易测试前的准备工作
     * 创建池并添加初始流动性
     */
    beforeEach(async function () {
      // === 第一步：创建池 ===
      const sqrtPriceX96 = ethers.parseUnits("79228162514264337593543950336", 0);
      
      const createParams = {
        token0: await tokenA.getAddress(),
        token1: await tokenB.getAddress(),
        fee: 3000,
        tickLower: -887220,
        tickUpper: 887220,
        sqrtPriceX96: sqrtPriceX96
      };

      await poolManager.createAndInitializePoolIfNecessary(createParams);
      
      // === 第二步：添加流动性为交易做准备 ===
      const amount0 = ethers.parseEther("1000");  // 添加1000个TokenA
      const amount1 = ethers.parseEther("1000");  // 添加1000个TokenB

      // 授权并添加流动性
      await tokenA.connect(addr1).approve(await positionManager.getAddress(), amount0);
      await tokenB.connect(addr1).approve(await positionManager.getAddress(), amount1);

      const mintParams = {
        token0: await tokenA.getAddress(),
        token1: await tokenB.getAddress(),
        index: 0,
        amount0Desired: amount0,
        amount1Desired: amount1,
        recipient: addr1.address,
        deadline: Math.floor(Date.now() / 1000) + 3600
      };

      // 执行流动性添加
      await positionManager.connect(addr1).mint(mintParams);
    });

    /**
     * 测试用例：应该能执行精确输入交易
     */
    it("应该能执行精确输入交易", async function () {
      // 设置交易参数
      const amountIn = ethers.parseEther("1");  // 用1个TokenA换取TokenB
      
      // 授权SwapRouter使用用户的TokenA
      await tokenA.connect(addr2).approve(await swapRouter.getAddress(), amountIn);

      // 构造精确输入交易参数
      const exactInputParams = {
        tokenIn: await tokenA.getAddress(),                          // 输入代币
        tokenOut: await tokenB.getAddress(),                         // 输出代币
        indexPath: [0],                                   // 使用池子索引0
        recipient: addr2.address,                         // 接收者
        deadline: Math.floor(Date.now() / 1000) + 3600,   // 过期时间
        amountIn: amountIn,                               // 输入数量
        amountOutMinimum: 0,                              // 最小输出（设为0用于测试）
        sqrtPriceLimitX96: "79228162514264337593543950300"  // 略小于当前价格的限制
      };

      // 记录交易前的TokenB余额
      const balanceBefore = await tokenB.balanceOf(addr2.address);
      
      // 执行精确输入交易
      await swapRouter.connect(addr2).exactInput(exactInputParams);
      
      // 记录交易后的TokenB余额
      const balanceAfter = await tokenB.balanceOf(addr2.address);

      // 验证交易成功：用户应该获得TokenB
      expect(balanceAfter).to.be.gt(balanceBefore);
    });
  });
});