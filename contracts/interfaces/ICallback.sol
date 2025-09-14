// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IMintCallback
 * @dev 流动性添加回调接口 - 当池子需要代币时调用
 */
interface IMintCallback {
    /**
     * @dev 添加流动性时的回调函数
     * @param amount0Owed 需要支付的token0数量
     * @param amount1Owed 需要支付的token1数量
     * @param data 传递给回调函数的额外数据
     */
    function mintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}

/**
 * @title ISwapCallback
 * @dev 交易回调接口 - 当执行交易时调用
 */
interface ISwapCallback {
    /**
     * @dev 执行交易时的回调函数
     * @param amount0Delta token0的变化量（正数表示需要支付，负数表示收到）
     * @param amount1Delta token1的变化量（正数表示需要支付，负数表示收到）
     * @param data 传递给回调函数的额外数据
     */
    function swapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}