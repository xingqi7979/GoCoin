// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IFactory.sol";
import "./Pool.sol";

/**
 * @title Factory
 * @dev 工厂合约 - 负责创建和管理所有交易池
 * 这是系统的核心合约之一，所有池子的创建都通过这里进行
 */
contract Factory is IFactory {
    /**
     * @dev 池子创建时的临时参数结构
     * 用于在创建池子时传递参数给Pool合约的构造函数
     */
    struct Parameters {
        address factory;    // 工厂合约地址
        address token0;     // 第一个代币地址
        address token1;     // 第二个代币地址
        int24 tickLower;    // 价格区间下限tick
        int24 tickUpper;    // 价格区间上限tick
        uint24 fee;         // 手续费率
    }

    /// @dev 当前的池子创建参数（临时存储，创建完成后会删除）
    Parameters public override parameters;

    /// @dev 池子地址映射：token0 => token1 => index => pool地址
    mapping(address => mapping(address => mapping(uint32 => address))) public override getPool;
    
    /// @dev 池子索引计数器，用于给新池子分配唯一索引
    uint32 public poolIndex;

    /**
     * @dev 创建新的交易池
     * @param token0 第一个代币地址
     * @param token1 第二个代币地址
     * @param tickLower 价格区间下限tick
     * @param tickUpper 价格区间上限tick
     * @param fee 手续费率（以万分之几为单位，如3000表示0.3%）
     * @return pool 新创建的池子地址
     */
    function createPool(
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external override returns (address pool) {
        // 参数验证
        require(token0 != token1, "IDENTICAL_ADDRESSES");
        // 确保token0地址小于token1地址（标准化排序）
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(tickLower < tickUpper, "INVALID_TICK_RANGE");
        require(fee > 0, "INVALID_FEE");

        // 分配新的池子索引
        uint32 index = poolIndex++;
        // 确保该索引下没有重复的池子
        require(getPool[token0][token1][index] == address(0), "POOL_EXISTS");

        // 设置临时参数，供Pool构造函数使用
        parameters = Parameters({
            factory: address(this),
            token0: token0,
            token1: token1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            fee: fee
        });

        // 使用CREATE2部署池子合约，确保地址可预测
        // salt使用token地址和索引的哈希，确保唯一性
        pool = address(new Pool{salt: keccak256(abi.encode(token0, token1, index))}());
        
        // 记录池子地址映射
        getPool[token0][token1][index] = pool;
        
        // 清除临时参数，节省gas
        delete parameters;

        // 发出池子创建事件
        emit PoolCreated(token0, token1, index, pool);
    }
}