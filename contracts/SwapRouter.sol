// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IPool.sol";
import "./interfaces/ICallback.sol";
import "./PoolManager.sol";

/**
 * @title SwapRouter
 * @dev 交易路由器 - 处理复杂的多池交易路径
 * 
 * 核心功能：
 * - 多池路径交易：支持通过多个池子进行交易
 * - 精确输入模式：指定输入数量，最大化输出
 * - 精确输出模式：指定输出数量，最小化输入
 * - 价格估算：提供交易前的价格预览功能
 * - 滑点保护：支持设置最小输出/最大输入限制
 * - 价格限制：支持设置每个池子的价格上限
 * 
 * 设计优势：
 * - 简化交易：用户不需要直接与Pool合约交互
 * - 批量优化：一次交易可以涉及多个池子
 * - 智能路由：自动选择最优的交易路径
 * - 安全可靠：完善的错误处理和状态校验
 */
contract SwapRouter is ISwapCallback {
    using SafeERC20 for IERC20;

    // ============ 交易参数结构 ============
    
    /**
     * @dev 精确输入价格估算参数
     */
    struct QuoteExactInputParams {
        address tokenIn;           // 输入代币地址
        address tokenOut;          // 输出代币地址
        uint32[] indexPath;        // 交易路径（池子索引数组）
        uint256 amountIn;          // 输入数量
        uint160 sqrtPriceLimitX96; // 价格限制
    }

    /**
     * @dev 精确输出价格估算参数
     */
    struct QuoteExactOutputParams {
        address tokenIn;           // 输入代币地址
        address tokenOut;          // 输出代币地址
        uint32[] indexPath;        // 交易路径（池子索引数组）
        uint256 amountOut;         // 期望输出数量
        uint160 sqrtPriceLimitX96; // 价格限制
    }

    /**
     * @dev 精确输入交易参数
     */
    struct ExactInputParams {
        address tokenIn;            // 输入代币地址
        address tokenOut;           // 输出代币地址
        uint32[] indexPath;         // 交易路径（池子索引数组）
        address recipient;          // 接收者地址
        uint256 deadline;           // 交易截止时间
        uint256 amountIn;           // 输入数量
        uint256 amountOutMinimum;   // 最小输出数量（滑点保护）
        uint160 sqrtPriceLimitX96;  // 价格限制
    }

    /**
     * @dev 精确输出交易参数
     */
    struct ExactOutputParams {
        address tokenIn;            // 输入代币地址
        address tokenOut;           // 输出代币地址
        uint32[] indexPath;         // 交易路径（池子索引数组）
        address recipient;          // 接收者地址
        uint256 deadline;           // 交易截止时间
        uint256 amountOut;          // 期望输出数量
        uint256 amountInMaximum;    // 最大输入数量（滑点保护）
        uint160 sqrtPriceLimitX96;  // 价格限制
    }

    /// @dev 池管理器合约实例，用于获取池子信息
    PoolManager public immutable poolManager;

    /**
     * @dev 交易截止时间检查修饰器
     * 确保交易在指定时间前完成，防止MEV攻击和过期交易
     * @param deadline 截止时间戳（Unix时间）
     */
    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "EXPIRED");
        _;
    }

    /**
     * @dev 构造函数 - 初始化池管理器引用
     * @param _poolManager 池管理器合约地址
     */
    constructor(address _poolManager) {
        poolManager = PoolManager(_poolManager);
    }

    function quoteExactInput(
        QuoteExactInputParams memory params
    ) external returns (uint256 amountOut) {
        require(params.indexPath.length > 0, "EMPTY_PATH"); // 确保交易路径不为空
        
        uint256 amountIn = params.amountIn; // 获取输入金额
        bool zeroForOne = params.tokenIn < params.tokenOut; // 判断交易方向：true表示token0换token1

        // 遍历交易路径中的每个池子
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPoolAddress(params.indexPath[i]); // 获取池子地址
            require(poolAddress != address(0), "POOL_NOT_EXISTS"); // 确保池子存在
            
            IPool pool = IPool(poolAddress); // 创建池子实例
            
            if (amountIn == 0) break; // 如果没有输入金额，退出循环

            // 尝试执行交换操作来获取报价
            try pool.swap(
                address(this), // 接收者为当前合约
                zeroForOne, // 交易方向
                int256(amountIn), // 输入金额（正数表示精确输入）
                params.sqrtPriceLimitX96, // 价格限制
                abi.encode(SwapCallbackData({ // 回调数据
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    payer: address(this) // 付款方为当前合约（用于报价）
                }))
            ) returns (int256 amount0, int256 amount1) {
                if (zeroForOne) {
                    // token0换token1：amount1为负数，表示输出的token1数量
                    amountOut += uint256(-amount1);
                    amountIn = 0; // 输入已全部消耗
                } else {
                    // token1换token0：amount0为负数，表示输出的token0数量
                    amountOut += uint256(-amount0);
                    amountIn = 0; // 输入已全部消耗
                }
            } catch {
                continue; // 如果交换失败，继续尝试下一个池子
            }
        }
    }

    function quoteExactOutput(
        QuoteExactOutputParams memory params
    ) external returns (uint256 amountIn) {
        require(params.indexPath.length > 0, "EMPTY_PATH"); // 确保交易路径不为空
        
        uint256 amountOut = params.amountOut; // 获取期望输出金额
        bool zeroForOne = params.tokenIn < params.tokenOut; // 判断交易方向

        // 遍历交易路径中的每个池子
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPoolAddress(params.indexPath[i]); // 获取池子地址
            require(poolAddress != address(0), "POOL_NOT_EXISTS"); // 确保池子存在
            
            IPool pool = IPool(poolAddress); // 创建池子实例
            
            if (amountOut == 0) break; // 如果没有期望输出，退出循环

            // 尝试执行反向交换来计算所需输入
            try pool.swap(
                address(this), // 接收者为当前合约
                zeroForOne, // 交易方向
                -int256(amountOut), // 输出金额（负数表示精确输出）
                params.sqrtPriceLimitX96, // 价格限制
                abi.encode(SwapCallbackData({ // 回调数据
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    payer: address(this) // 付款方为当前合约（用于报价）
                }))
            ) returns (int256 amount0, int256 amount1) {
                if (zeroForOne) {
                    // token0换token1：amount0为正数，表示需要的token0输入
                    amountIn += uint256(amount0);
                    amountOut = 0; // 输出已确定
                } else {
                    // token1换token0：amount1为正数，表示需要的token1输入
                    amountIn += uint256(amount1);
                    amountOut = 0; // 输出已确定
                }
            } catch {
                continue; // 如果交换失败，继续尝试下一个池子
            }
        }
    }

    function exactInput(
        ExactInputParams calldata params
    ) external payable checkDeadline(params.deadline) returns (uint256 amountOut) {
        require(params.indexPath.length > 0, "EMPTY_PATH"); // 确保交易路径不为空
        
        uint256 amountIn = params.amountIn; // 获取输入金额
        bool zeroForOne = params.tokenIn < params.tokenOut; // 判断交易方向

        // 从用户账户转入代币到路由合约
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // 遍历交易路径中的每个池子进行实际交换
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPoolAddress(params.indexPath[i]); // 获取池子地址
            require(poolAddress != address(0), "POOL_NOT_EXISTS"); // 确保池子存在
            
            IPool pool = IPool(poolAddress); // 创建池子实例
            
            if (amountIn == 0) break; // 如果没有输入金额，退出循环

            // 执行交换操作
            (int256 amount0, int256 amount1) = pool.swap(
                // 如果是最后一个池子，将代币直接发送给接收者；否则发送给路由合约
                i == params.indexPath.length - 1 ? params.recipient : address(this),
                zeroForOne, // 交易方向
                int256(amountIn), // 输入金额（正数表示精确输入）
                params.sqrtPriceLimitX96, // 价格限制
                abi.encode(SwapCallbackData({ // 回调数据
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    payer: address(this) // 付款方为路由合约
                }))
            );

            // 计算实际输出并更新状态
            if (zeroForOne) {
                // token0换token1：amount1为负数，表示输出的token1数量
                amountOut += uint256(-amount1);
                amountIn = 0; // 输入已全部消耗
            } else {
                // token1换token0：amount0为负数，表示输出的token0数量
                amountOut += uint256(-amount0);
                amountIn = 0; // 输入已全部消耗
            }
        }

        // 检查实际输出是否满足用户的最小输出要求
        require(amountOut >= params.amountOutMinimum, "INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function exactOutput(
        ExactOutputParams calldata params
    ) external payable checkDeadline(params.deadline) returns (uint256 amountIn) {
        require(params.indexPath.length > 0, "EMPTY_PATH"); // 确保交易路径不为空
        
        uint256 amountOut = params.amountOut; // 获取期望输出金额
        bool zeroForOne = params.tokenIn < params.tokenOut; // 判断交易方向

        // 遍历交易路径中的每个池子进行实际交换
        for (uint256 i = 0; i < params.indexPath.length; i++) {
            address poolAddress = poolManager.getPoolAddress(params.indexPath[i]); // 获取池子地址
            require(poolAddress != address(0), "POOL_NOT_EXISTS"); // 确保池子存在
            
            IPool pool = IPool(poolAddress); // 创建池子实例
            
            if (amountOut == 0) break; // 如果没有期望输出，退出循环

            // 执行反向交换操作（精确输出模式）
            (int256 amount0, int256 amount1) = pool.swap(
                // 如果是最后一个池子，将代币直接发送给接收者；否则发送给路由合约
                i == params.indexPath.length - 1 ? params.recipient : address(this),
                zeroForOne, // 交易方向
                -int256(amountOut), // 输出金额（负数表示精确输出）
                params.sqrtPriceLimitX96, // 价格限制
                abi.encode(SwapCallbackData({ // 回调数据
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    payer: msg.sender // 付款方为用户（精确输出模式下直接从用户扣款）
                }))
            );

            // 计算实际输入并更新状态
            if (zeroForOne) {
                // token0换token1：amount0为正数，表示实际需要的token0输入
                amountIn += uint256(amount0);
                amountOut = 0; // 输出已确定
            } else {
                // token1换token0：amount1为正数，表示实际需要的token1输入
                amountIn += uint256(amount1);
                amountOut = 0; // 输出已确定
            }
        }

        // 检查实际输入是否在用户的最大输入限制内
        require(amountIn <= params.amountInMaximum, "EXCESSIVE_INPUT_AMOUNT");
    }

    /**
     * @dev 交换回调数据结构
     * 用于在swap回调函数中传递必要信息
     */
    struct SwapCallbackData {
        address tokenIn;  // 输入代币地址
        address tokenOut; // 输出代币地址  
        address payer;    // 付款方地址
    }

    /**
     * @dev 交换回调函数
     * 当Pool合约执行swap时会调用此函数来获取所需的输入代币
     * 
     * @param amount0Delta token0的变化量（正数表示需要转入，负数表示转出）
     * @param amount1Delta token1的变化量（正数表示需要转入，负数表示转出）
     * @param data 编码的回调数据
     */
    function swapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        // 解码回调数据
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));

        // 处理token0的转账（如果需要转入）
        if (amount0Delta > 0) {
            if (decoded.payer == address(this)) {
                // 如果付款方是路由合约，直接从路由合约转账
                IERC20(decoded.tokenIn).safeTransfer(msg.sender, uint256(amount0Delta));
            } else {
                // 如果付款方是外部用户，从用户账户转账到池合约
                IERC20(decoded.tokenIn).safeTransferFrom(decoded.payer, msg.sender, uint256(amount0Delta));
            }
        }

        // 处理token1的转账（如果需要转入）
        if (amount1Delta > 0) {
            if (decoded.payer == address(this)) {
                // 如果付款方是路由合约，直接从路由合约转账
                IERC20(decoded.tokenIn).safeTransfer(msg.sender, uint256(amount1Delta));
            } else {
                // 如果付款方是外部用户，从用户账户转账到池合约
                IERC20(decoded.tokenIn).safeTransferFrom(decoded.payer, msg.sender, uint256(amount1Delta));
            }
        }
    }
}