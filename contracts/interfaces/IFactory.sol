// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IFactory
 * @dev 工厂合约接口 - 负责创建和管理交易池
 */
interface IFactory {
    /**
     * @dev 当创建新池时发出的事件
     * @param token0 第一个代币地址
     * @param token1 第二个代币地址
     * @param index 池子索引
     * @param pool 新创建的池子地址
     */
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint32 indexed index,
        address pool
    );

    /**
     * @dev 根据代币对和索引获取池子地址
     * @param token0 第一个代币地址
     * @param token1 第二个代币地址
     * @param index 池子索引
     * @return pool 池子地址，如果不存在返回零地址
     */
    function getPool(
        address token0,
        address token1,
        uint32 index
    ) external view returns (address pool);

    /**
     * @dev 创建新的交易池
     * @param token0 第一个代币地址
     * @param token1 第二个代币地址
     * @param tickLower 价格区间下限tick
     * @param tickUpper 价格区间上限tick
     * @param fee 交易手续费（以万分之几为单位）
     * @return pool 新创建的池子地址
     */
    function createPool(
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external returns (address pool);

    /**
     * @dev 获取池子创建时的临时参数
     * @return factory 工厂合约地址
     * @return token0 第一个代币地址
     * @return token1 第二个代币地址
     * @return tickLower 价格区间下限tick
     * @return tickUpper 价格区间上限tick
     * @return fee 交易手续费
     */
    function parameters()
        external
        view
        returns (
            address factory,
            address token0,
            address token1,
            int24 tickLower,
            int24 tickUpper,
            uint24 fee
        );
}