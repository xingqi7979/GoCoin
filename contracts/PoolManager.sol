// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Factory.sol";
import "./interfaces/IPool.sol";

/**
 * @title PoolManager
 * @dev 池管理合约 - 继承自Factory，提供池子管理和查询功能
 * 对应前端的Pool页面，负责池子的创建、初始化和信息查询
 */
contract PoolManager is Factory {
    /**
     * @dev 池子信息结构，包含池子的所有关键数据
     * 用于前端展示池子列表和详情
     */
    struct PoolInfo {
        address token0;        // 第一个代币地址
        address token1;        // 第二个代币地址
        uint32 index;          // 池子索引
        int24 fee;             // 手续费率
        int24 tickLower;       // 价格区间下限tick
        int24 tickUpper;       // 价格区间上限tick
        int24 tick;            // 当前价格tick
        uint160 sqrtPriceX96;  // 当前价格的平方根（Q64.96格式）
        uint128 liquidity;     // 当前总流动性
    }

    /**
     * @dev 创建和初始化池子的参数结构
     */
    struct CreateAndInitializeParams {
        address token0;        // 第一个代币地址
        address token1;        // 第二个代币地址
        uint24 fee;           // 手续费率
        int24 tickLower;      // 价格区间下限tick
        int24 tickUpper;      // 价格区间上限tick
        uint160 sqrtPriceX96; // 初始价格的平方根
    }

    /**
     * @dev 交易对结构，用于存储所有存在的token对
     */
    struct Pair {
        address token0;  // 第一个代币地址
        address token1;  // 第二个代币地址
    }

    /// @dev 记录交易对是否已存在：token0 => token1 => 是否存在
    mapping(address => mapping(address => bool)) public pairExists;
    
    /// @dev 所有交易对的数组
    Pair[] public pairs;
    
    /// @dev 所有池子地址的数组，用于快速遍历
    address[] public allPools;

    /**
     * @dev 创建并初始化池子（如果需要的话）
     * 这是一个便捷函数，既可以创建池子也可以初始化价格
     * @param params 创建和初始化参数
     * @return pool 创建的池子地址
     */
    function createAndInitializePoolIfNecessary(
        CreateAndInitializeParams calldata params
    ) external payable returns (address pool) {
        // 确保token地址按标准顺序排列
        (address token0, address token1) = params.token0 < params.token1 
            ? (params.token0, params.token1) 
            : (params.token1, params.token0);

        // 如果是新的交易对，添加到pairs数组
        if (!pairExists[token0][token1]) {
            pairs.push(Pair({token0: token0, token1: token1}));
            pairExists[token0][token1] = true;
        }

        // 调用父合约的createPool函数创建池子
        pool = this.createPool(
            token0,
            token1,
            params.tickLower,
            params.tickUpper,
            params.fee
        );

        // 将新池子添加到全局池子列表
        allPools.push(pool);

        // 初始化池子的价格
        IPool(pool).initialize(params.sqrtPriceX96);
    }

    /**
     * @dev 获取所有池子的信息
     * 前端调用此函数获取池子列表数据
     * @return poolsInfo 所有池子的信息数组
     */
    function getAllPools() external view returns (PoolInfo[] memory poolsInfo) {
        uint256 length = allPools.length;
        poolsInfo = new PoolInfo[](length);

        // 遍历所有池子，收集详细信息
        for (uint256 i = 0; i < length; i++) {
            address poolAddress = allPools[i];
            IPool pool = IPool(poolAddress);

            // 构造池子信息结构
            poolsInfo[i] = PoolInfo({
                token0: pool.token0(),
                token1: pool.token1(),
                index: uint32(i),                    // 使用数组索引作为显示索引
                fee: int24(uint24(pool.fee())),      // 类型转换
                tickLower: pool.tickLower(),
                tickUpper: pool.tickUpper(),
                tick: pool.tick(),
                sqrtPriceX96: pool.sqrtPriceX96(),
                liquidity: pool.liquidity()
            });
        }
    }

    /**
     * @dev 获取所有交易对
     * 前端使用此函数填充token选择下拉框
     * @return 所有交易对的数组
     */
    function getPairs() external view returns (Pair[] memory) {
        return pairs;
    }

    /**
     * @dev 获取池子总数
     * @return 当前系统中的池子数量
     */
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }

    /**
     * @dev 根据索引获取池子地址
     * @param index 池子在allPools数组中的索引
     * @return 池子地址
     */
    function getPoolAddress(uint256 index) external view returns (address) {
        require(index < allPools.length, "INVALID_INDEX");
        return allPools[index];
    }
}