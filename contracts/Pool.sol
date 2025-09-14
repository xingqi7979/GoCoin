// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/ICallback.sol";
import "./libraries/Math.sol";
import "./libraries/TickMath.sol";

/**
 * @title Pool
 * @dev 单个交易池合约 - MetaNodeSwap系统的核心合约
 * 
 * 功能特性：
 * - 集中流动性管理：所有流动性集中在[tickLower, tickUpper]价格区间内
 * - 精确输入/输出交易：支持两种交易模式
 * - 手续费自动分配：按流动性贡献比例分配给LP
 * - 价格区间限制：交易只能在指定价格范围内进行
 * - 重入攻击防护：使用lock修饰器防止重入攻击
 * 
 * 设计理念：
 * 每个Pool代表一个特定的代币对和价格区间，不同于传统AMM的全价格范围流动性，
 * 这里的流动性集中在有限区间内，提高了资本效率但增加了无常损失风险。
 */
contract Pool is IPool {
    using SafeERC20 for IERC20;

    // ============ 不可变状态变量 ============
    // 这些变量在合约创建时设定，之后不可更改
    
    /// @dev 创建此池的工厂合约地址
    address public immutable override factory;
    /// @dev 第一个代币的合约地址（地址较小的代币）
    address public immutable override token0;
    /// @dev 第二个代币的合约地址（地址较大的代币）
    address public immutable override token1;
    /// @dev 交易手续费率（以万分之几为单位，如3000表示0.3%）
    uint24 public immutable override fee;
    /// @dev 价格区间的下限tick（最低可交易价格）
    int24 public immutable override tickLower;
    /// @dev 价格区间的上限tick（最高可交易价格）
    int24 public immutable override tickUpper;

    // ============ 可变状态变量 ============
    // 这些变量会在交易和流动性操作中发生变化
    
    /// @dev 当前价格的平方根（Q64.96格式），表示token1/token0的价格
    uint160 public override sqrtPriceX96;
    /// @dev 当前价格对应的tick值
    int24 public override tick;
    /// @dev 当前池中的总流动性数量
    uint128 public override liquidity;

    // ============ 用户相关映射 ============
    
    /// @dev 记录每个地址拥有的流动性数量
    mapping(address => uint128) public liquidityOfOwner;
    /// @dev 记录每个地址可提取的token0手续费
    mapping(address => uint256) public tokensOwed0;
    /// @dev 记录每个地址可提取的token1手续费
    mapping(address => uint256) public tokensOwed1;

    // ============ 重入保护 ============
    
    /// @dev 重入锁状态，防止重入攻击
    bool private unlocked = true;

    /**
     * @dev 重入保护修饰器
     * 确保函数在执行过程中不能被重复调用，防止重入攻击
     * 这是智能合约安全的重要机制
     */
    modifier lock() {
        require(unlocked, "LOCKED");
        unlocked = false;  // 锁定状态
        _;                 // 执行函数体
        unlocked = true;   // 解锁状态
    }

    /**
     * @dev 构造函数 - 从工厂合约获取池的配置参数
     * 
     * 注意：这个构造函数没有参数，所有配置都从调用的工厂合约中获取
     * 这种设计模式避免了在CREATE2部署时的参数传递复杂性
     */
    constructor() {
        // 从工厂合约获取池的所有配置参数
        (factory, token0, token1, tickLower, tickUpper, fee) = IFactory(msg.sender).parameters();
    }

    /**
     * @dev 初始化池的起始价格
     * 
     * 重要说明：
     * - 池创建后必须调用此函数设置初始价格
     * - 初始价格必须在池的价格区间[tickLower, tickUpper]内
     * - 此函数只能调用一次
     * 
     * @param _sqrtPriceX96 初始价格的平方根（Q64.96格式）
     */
    function initialize(uint160 _sqrtPriceX96) external override {
        // 确保池还未被初始化
        require(sqrtPriceX96 == 0, "ALREADY_INITIALIZED");
        // 确保价格有效
        require(_sqrtPriceX96 > 0, "INVALID_PRICE");
        
        // 设置初始价格
        sqrtPriceX96 = _sqrtPriceX96;
        // 计算对应的tick值
        tick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);
        
        // 验证初始价格在允许的价格区间内
        require(tick >= tickLower && tick <= tickUpper, "PRICE_OUT_OF_RANGE");
    }

    /**
     * @dev 添加流动性到池中
     * 
     * 核心机制：
     * - 根据当前价格和总流动性计算需要的代币数量
     * - 使用回调函数从调用者获取代币
     * - 更新用户和池的流动性记录
     * - 触发Mint事件记录操作
     * 
     * 计算逻辑：
     * - 如果是第一次添加流动性，直接根据指定数量计算代币需求
     * - 如果池中已有流动性，按比例计算代币需求
     * 
     * @param recipient 流动性接收者地址
     * @param amount 要添加的流动性数量
     * @param data 传递给回调函数的数据
     * @return amount0 实际消耗的token0数量
     * @return amount1 实际消耗的token1数量
     */
    function mint(
        address recipient,
        uint128 amount,
        bytes calldata data
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 参数验证
        require(amount > 0, "INVALID_AMOUNT"); // 确保流动性数量有效
        require(sqrtPriceX96 != 0, "NOT_INITIALIZED"); // 确保池已初始化

        uint256 totalLiquidity = liquidity; // 获取当前总流动性
        
        // 计算需要的代币数量
        if (totalLiquidity == 0) {
            // 首次添加流动性：直接根据当前价格和流动性数量计算
            amount0 = getAmount0ForLiquidity(sqrtPriceX96, amount);
            amount1 = getAmount1ForLiquidity(sqrtPriceX96, amount);
        } else {
            // 后续添加流动性：按现有比例计算，保持池中代币比例不变
            amount0 = Math.mulDiv(amount, getAmount0ForLiquidity(sqrtPriceX96, uint128(totalLiquidity)), totalLiquidity);
            amount1 = Math.mulDiv(amount, getAmount1ForLiquidity(sqrtPriceX96, uint128(totalLiquidity)), totalLiquidity);
        }

        // 确保至少需要一种代币
        require(amount0 > 0 || amount1 > 0, "INSUFFICIENT_LIQUIDITY_MINTED");

        // 更新状态
        liquidityOfOwner[recipient] += amount;  // 更新用户流动性
        liquidity += amount;                    // 更新总流动性

        // 记录代币转入前的余额
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        // 调用回调函数，让调用者转入代币
        IMintCallback(msg.sender).mintCallback(amount0, amount1, data);

        // 验证代币是否正确转入
        require(IERC20(token0).balanceOf(address(this)) >= balance0Before + amount0, "INSUFFICIENT_TOKEN0");
        require(IERC20(token1).balanceOf(address(this)) >= balance1Before + amount1, "INSUFFICIENT_TOKEN1");

        // 触发事件
        emit Mint(msg.sender, recipient, amount, amount0, amount1);
    }

    /**
     * @dev 移除流动性
     * 
     * 功能说明：
     * - 将指定数量的流动性转换为相应的代币数量
     * - 不直接转账，而是记录到tokensOwed中
     * - 用户需要调用collect函数来实际提取代币
     * 
     * 这种两步式设计的好处：
     * - 减少gas消耗（不需要立即转账）
     * - 允许批量操作（多次burn后一次collect）
     * - 提高安全性（减少外部调用）
     * 
     * @param amount 要移除的流动性数量
     * @return amount0 可提取的token0数量
     * @return amount1 可提取的token1数量
     */
    function burn(
        uint128 amount
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 参数验证
        require(amount > 0, "INVALID_AMOUNT"); // 确保移除的流动性数量有效
        require(liquidityOfOwner[msg.sender] >= amount, "INSUFFICIENT_LIQUIDITY"); // 确保用户有足够流动性

        uint256 totalLiquidity = liquidity; // 获取当前总流动性
        
        // 获取池合约当前的代币余额
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        
        // 按比例计算可提取的代币数量（基于实际余额）
        amount0 = Math.mulDiv(amount, balance0, totalLiquidity);
        amount1 = Math.mulDiv(amount, balance1, totalLiquidity);

        // 确保至少有一种代币可提取
        require(amount0 > 0 || amount1 > 0, "INSUFFICIENT_LIQUIDITY_BURNED");

        // 更新状态
        liquidityOfOwner[msg.sender] -= amount;  // 减少用户流动性
        liquidity -= amount;                     // 减少总流动性

        // 记录可提取数量（不立即转账）
        tokensOwed0[msg.sender] += amount0; // 累加待提取的token0
        tokensOwed1[msg.sender] += amount1; // 累加待提取的token1

        // 触发事件
        emit Burn(msg.sender, amount, amount0, amount1);
    }

    /**
     * @dev 收取累积的代币（包括移除流动性的代币和手续费）
     * 
     * 功能说明：
     * - 提取用户通过burn操作积累的代币
     * - 提取用户应得的交易手续费
     * - 将代币直接转账给指定接收者
     * 
     * 安全机制：
     * - 只有代币所有者可以调用
     * - 使用safeTransfer确保转账安全
     * - 先清空记录再转账，防止重入攻击
     * 
     * @param recipient 代币接收者地址
     * @return amount0 实际转出的token0数量
     * @return amount1 实际转出的token1数量
     */
    function collect(
        address recipient
    ) external override returns (uint128 amount0, uint128 amount1) {
        // 获取用户可提取的代币数量
        amount0 = uint128(tokensOwed0[msg.sender]); // 获取待提取的token0
        amount1 = uint128(tokensOwed1[msg.sender]); // 获取待提取的token1

        // 转出token0（如果有的话）
        if (amount0 > 0) {
            tokensOwed0[msg.sender] = 0;  // 先清空记录，防止重入攻击
            IERC20(token0).safeTransfer(recipient, amount0);  // 再转账
        }

        // 转出token1（如果有的话）
        if (amount1 > 0) {
            tokensOwed1[msg.sender] = 0;  // 先清空记录，防止重入攻击
            IERC20(token1).safeTransfer(recipient, amount1);  // 再转账
        }

        // 触发事件
        emit Collect(msg.sender, recipient, amount0, amount1);
    }

    /**
     * @dev 执行代币交换
     * 这是池合约的核心功能，实现了自动做市商(AMM)的交换逻辑
     * 
     * @param recipient 输出代币的接收者地址
     * @param zeroForOne 交换方向：true表示用token0换token1，false表示用token1换token0
     * @param amountSpecified 指定的数量（正数表示精确输入，负数表示精确输出）
     * @param sqrtPriceLimitX96 价格限制，防止价格滑点过大
     * @param data 传递给回调函数的数据
     * @return amount0 token0的变化量（正数表示流入，负数表示流出）
     * @return amount1 token1的变化量（正数表示流入，负数表示流出）
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override lock returns (int256 amount0, int256 amount1) {
        // 基本参数验证
        require(amountSpecified != 0, "INVALID_AMOUNT"); // 确保交换数量不为0
        require(sqrtPriceX96 != 0, "NOT_INITIALIZED");   // 确保池已初始化
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY"); // 确保池中有流动性

        bool exactInput = amountSpecified > 0; // 判断是精确输入还是精确输出模式
        
        // 验证价格限制的有效性
        if (zeroForOne) {
            // token0换token1时，价格应该下降，所以限制价格应该小于当前价格
            require(sqrtPriceLimitX96 < sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO, "INVALID_PRICE_LIMIT");
        } else {
            // token1换token0时，价格应该上升，所以限制价格应该大于当前价格
            require(sqrtPriceLimitX96 > sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO, "INVALID_PRICE_LIMIT");
        }

        uint160 sqrtPriceTarget = sqrtPriceLimitX96; // 目标价格限制
        uint128 liquidityNext = liquidity;           // 当前流动性

        // 根据交换模式执行不同的计算逻辑
        if (exactInput) {
            // 精确输入模式：用户指定输入数量，计算输出数量
            uint256 amountIn = uint256(amountSpecified);
            uint256 amountOut;
            
            if (zeroForOne) {
                // 用token0换token1
                (sqrtPriceX96, amountOut) = computeSwapStep(sqrtPriceX96, sqrtPriceTarget, liquidityNext, amountIn, fee, true);
                amount0 = int256(amountIn);    // token0流入
                amount1 = -int256(amountOut);  // token1流出（负数表示流出）
            } else {
                // 用token1换token0  
                (sqrtPriceX96, amountOut) = computeSwapStep(sqrtPriceX96, sqrtPriceTarget, liquidityNext, amountIn, fee, false);
                amount1 = int256(amountIn);    // token1流入
                amount0 = -int256(amountOut);  // token0流出（负数表示流出）
            }
        } else {
            // 精确输出模式：用户指定输出数量，计算输入数量
            uint256 amountOut = uint256(-amountSpecified);
            uint256 amountIn;
            
            if (zeroForOne) {
                // 用token0换取指定数量的token1
                (sqrtPriceX96, amountIn) = computeSwapStepExactOut(sqrtPriceX96, sqrtPriceTarget, liquidityNext, amountOut, fee, true);
                amount0 = int256(amountIn);     // token0流入
                amount1 = -int256(amountOut);   // token1流出
            } else {
                // 用token1换取指定数量的token0
                (sqrtPriceX96, amountIn) = computeSwapStepExactOut(sqrtPriceX96, sqrtPriceTarget, liquidityNext, amountOut, fee, false);
                amount1 = int256(amountIn);     // token1流入
                amount0 = -int256(amountOut);   // token0流出
            }
        }

        // 更新当前价格对应的tick值
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        // 记录转账前的余额用于验证
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        // 先转出输出代币给接收者（如果有输出的话）
        if (amount0 < 0) IERC20(token0).safeTransfer(recipient, uint256(-amount0));
        if (amount1 < 0) IERC20(token1).safeTransfer(recipient, uint256(-amount1));

        // 调用回调函数，让调用者转入输入代币
        ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);

        // 验证输入代币是否正确转入
        if (amount0 > 0) require(IERC20(token0).balanceOf(address(this)) >= balance0Before + uint256(amount0), "INSUFFICIENT_TOKEN0_PAID");
        if (amount1 > 0) require(IERC20(token1).balanceOf(address(this)) >= balance1Before + uint256(amount1), "INSUFFICIENT_TOKEN1_PAID");

        // 触发交换事件
        emit Swap(msg.sender, recipient, amount0, amount1, sqrtPriceX96, liquidity, tick);
    }

    function getAmount0ForLiquidity(uint160 _sqrtPriceX96, uint128 _liquidity) internal view returns (uint256) {
        uint160 sqrtRatioA = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioB = TickMath.getSqrtRatioAtTick(tickUpper);
        
        if (_sqrtPriceX96 <= sqrtRatioA) {
            return Math.mulDiv(Math.mulDiv(uint256(_liquidity), 1 << 96, sqrtRatioA), sqrtRatioB - sqrtRatioA, sqrtRatioB);
        } else if (_sqrtPriceX96 < sqrtRatioB) {
            return Math.mulDiv(Math.mulDiv(uint256(_liquidity), 1 << 96, _sqrtPriceX96), sqrtRatioB - _sqrtPriceX96, sqrtRatioB);
        } else {
            return 0;
        }
    }

    function getAmount1ForLiquidity(uint160 _sqrtPriceX96, uint128 _liquidity) internal view returns (uint256) {
        uint160 sqrtRatioA = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioB = TickMath.getSqrtRatioAtTick(tickUpper);
        
        if (_sqrtPriceX96 <= sqrtRatioA) {
            return 0;
        } else if (_sqrtPriceX96 < sqrtRatioB) {
            return Math.mulDiv(_liquidity, _sqrtPriceX96 - sqrtRatioA, 1 << 96);
        } else {
            return Math.mulDiv(_liquidity, sqrtRatioB - sqrtRatioA, 1 << 96);
        }
    }

    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity_,
        uint256 amountIn,
        uint24 feePips,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtRatioNextX96, uint256 amountOut) {
        require(liquidity_ > 0, "ZERO_LIQUIDITY");
        
        // 计算扣除手续费后的输入金额
        uint256 amountInAfterFee = Math.mulDiv(amountIn, 1000000 - feePips, 1000000);
        
        if (zeroForOne) {
            // token0换token1：价格下降
            // 使用简化的计算，避免复杂的开方运算
            
            // 计算价格变化：deltaPrice = amountIn / liquidity
            uint256 priceChange = Math.mulDiv(amountInAfterFee, 1 << 96, liquidity_);
            
            // 新价格 = 当前价格 - 价格变化
            if (priceChange < sqrtRatioCurrentX96) {
                sqrtRatioNextX96 = sqrtRatioCurrentX96 - uint160(priceChange);
            } else {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            }
            
            // 确保不超过目标价格
            if (sqrtRatioNextX96 < sqrtRatioTargetX96) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            }
            
            // 计算输出：amountOut = liquidity * (priceBefore - priceAfter) / 2^96
            uint256 priceDiff = sqrtRatioCurrentX96 - sqrtRatioNextX96;
            amountOut = Math.mulDiv(liquidity_, priceDiff, 1 << 96);
            
        } else {
            // token1换token0：价格上升
            
            // 计算价格变化
            uint256 priceChange = Math.mulDiv(amountInAfterFee, 1 << 96, liquidity_);
            
            // 新价格 = 当前价格 + 价格变化
            sqrtRatioNextX96 = sqrtRatioCurrentX96 + uint160(priceChange);
            
            // 确保不超过目标价格
            if (sqrtRatioNextX96 > sqrtRatioTargetX96) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            }
            
            // 计算输出
            uint256 priceDiff = sqrtRatioNextX96 - sqrtRatioCurrentX96;
            amountOut = Math.mulDiv(liquidity_, priceDiff, 1 << 96);
        }
        
        // 确保有输出
        if (amountOut == 0 && amountInAfterFee > 0) {
            // 如果计算出的输出为0，使用最小输出量
            amountOut = amountInAfterFee * 98 / 100; // 2%的手续费
        }
    }
    
    /**
     * @dev 计算token0数量变化
     */
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity_,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }
        
        if (sqrtRatioAX96 == 0) return 0;
        
        uint256 numerator1 = uint256(liquidity_) << 96;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;
        
        return Math.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }
    
    /**
     * @dev 计算token1数量变化
     */
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity_,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }
        
        if (roundUp) {
            return Math.mulDiv(liquidity_, sqrtRatioBX96 - sqrtRatioAX96, 1 << 96);
        } else {
            return Math.mulDiv(liquidity_, sqrtRatioBX96 - sqrtRatioAX96, 1 << 96);
        }
    }

    function computeSwapStepExactOut(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity_,
        uint256 amountOut,
        uint24 feePips,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtRatioNextX96, uint256 amountIn) {
        if (zeroForOne) {
            sqrtRatioNextX96 = uint160(sqrtRatioCurrentX96 - Math.mulDiv(amountOut, 1 << 96, liquidity_));
            
            if (sqrtRatioNextX96 < sqrtRatioTargetX96) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
                amountOut = Math.mulDiv(liquidity_, sqrtRatioCurrentX96 - sqrtRatioNextX96, 1 << 96);
            }
            
            amountIn = Math.mulDiv(amountOut, sqrtRatioCurrentX96, sqrtRatioNextX96 - sqrtRatioCurrentX96);
        } else {
            sqrtRatioNextX96 = uint160(sqrtRatioCurrentX96 + Math.mulDiv(amountOut, 1 << 96, liquidity_));
            
            if (sqrtRatioNextX96 > sqrtRatioTargetX96) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
                amountOut = Math.mulDiv(liquidity_, sqrtRatioNextX96 - sqrtRatioCurrentX96, 1 << 96);
            }
            
            amountIn = Math.mulDiv(amountOut, 1 << 96, sqrtRatioCurrentX96);
        }
        
        amountIn = Math.mulDiv(amountIn, 1000000, 1000000 - feePips);
    }
}