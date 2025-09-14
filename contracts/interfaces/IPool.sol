// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IPool
 * @dev 交易池接口 - 定义单个交易池的核心功能
 */
interface IPool {
    /**
     * @dev 添加流动性时发出的事件
     * @param sender 调用者地址
     * @param owner 流动性持有者地址
     * @param amount 添加的流动性数量
     * @param amount0 实际使用的token0数量
     * @param amount1 实际使用的token1数量
     */
    event Mint(
        address sender,
        address indexed owner,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @dev 收取手续费时发出的事件
     * @param owner 流动性持有者地址
     * @param recipient 接收手续费的地址
     * @param amount0 收取的token0手续费数量
     * @param amount1 收取的token1手续费数量
     */
    event Collect(
        address indexed owner,
        address recipient,
        uint128 amount0,
        uint128 amount1
    );

    /**
     * @dev 移除流动性时发出的事件
     * @param owner 流动性持有者地址
     * @param amount 移除的流动性数量
     * @param amount0 移除的token0数量
     * @param amount1 移除的token1数量
     */
    event Burn(
        address indexed owner,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @dev 执行交易时发出的事件
     * @param sender 交易发起者地址
     * @param recipient 交易接收者地址
     * @param amount0 token0变化量
     * @param amount1 token1变化量
     * @param sqrtPriceX96 交易后的价格
     * @param liquidity 当前流动性
     * @param tick 当前tick
     */
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    // 只读函数 - 获取池子基本信息
    function factory() external view returns (address);    // 工厂合约地址
    function token0() external view returns (address);     // 第一个代币地址
    function token1() external view returns (address);     // 第二个代币地址
    function fee() external view returns (uint24);         // 手续费率
    function tickLower() external view returns (int24);    // 价格区间下限
    function tickUpper() external view returns (int24);    // 价格区间上限
    function sqrtPriceX96() external view returns (uint160); // 当前价格的平方根
    function tick() external view returns (int24);         // 当前tick
    function liquidity() external view returns (uint128);  // 当前流动性

    /**
     * @dev 初始化池子价格
     * @param sqrtPriceX96 初始价格的平方根（Q64.96格式）
     */
    function initialize(uint160 sqrtPriceX96) external;

    /**
     * @dev 添加流动性
     * @param recipient 流动性接收者地址
     * @param amount 要添加的流动性数量
     * @param data 回调函数的数据
     * @return amount0 实际消耗的token0数量
     * @return amount1 实际消耗的token1数量
     */
    function mint(
        address recipient,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /**
     * @dev 收取累积的手续费
     * @param recipient 手续费接收者地址
     * @return amount0 收取的token0手续费
     * @return amount1 收取的token1手续费
     */
    function collect(
        address recipient
    ) external returns (uint128 amount0, uint128 amount1);

    /**
     * @dev 移除流动性
     * @param amount 要移除的流动性数量
     * @return amount0 移除的token0数量
     * @return amount1 移除的token1数量
     */
    function burn(
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    /**
     * @dev 执行代币交换
     * @param recipient 交换结果接收者地址
     * @param zeroForOne 是否用token0换token1
     * @param amountSpecified 指定的交换数量（正数为精确输入，负数为精确输出）
     * @param sqrtPriceLimitX96 价格限制
     * @param data 回调函数的数据
     * @return amount0 token0的变化量
     * @return amount1 token1的变化量
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}