// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Math
 * @dev 数学计算库 - 提供高精度数学运算功能
 * 主要用于处理大数乘除运算和开平方根运算，防止溢出
 */
library Math {
    /**
     * @dev 高精度乘除运算 (a * b) / denominator
     * 基于OpenZeppelin的FullMath实现，可以处理中间结果超过uint256的情况
     * @param a 被乘数
     * @param b 乘数
     * @param denominator 除数，不能为0
     * @return result 运算结果
     */
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 处理边界情况
        if (a == 0 || b == 0) return 0;
        require(denominator > 0, "ZERO_DENOMINATOR");

        // 512位乘法 a * b = (hi, lo)
        uint256 prod0; // 乘积的低256位
        uint256 prod1; // 乘积的高256位
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // 处理溢出
        if (prod1 == 0) {
            // 没有溢出，直接除法
            return prod0 / denominator;
        }

        // 确保结果小于2^256
        require(denominator > prod1, "Math: mulDiv overflow");

        ///////////////////////////////////////////////
        // 512位除法：计算floor((a * b) / denominator)
        ///////////////////////////////////////////////

        // 计算余数
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
            
            // 从prod1:prod0中减去余数
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // 提取denominator的最大2的幂因子
        // 这总是 >= 1
        uint256 twos = denominator & (~denominator + 1);
        assembly {
            // 除以twos
            denominator := div(denominator, twos)
            
            // 除以twos
            prod0 := div(prod0, twos)
            
            // 翻转twos，使其变成2^256 / twos
            twos := add(div(sub(0, twos), twos), 1)
        }

        // 将高位移位到正确位置
        prod0 |= prod1 * twos;

        // 计算modular multiplicative inverse
        // 使用Newton-Raphson迭代计算逆元
        uint256 inverse = (3 * denominator) ^ 2;
        
        // 6次迭代，每次加倍正确的位数
        inverse *= 2 - denominator * inverse; // mod 2^8
        inverse *= 2 - denominator * inverse; // mod 2^16
        inverse *= 2 - denominator * inverse; // mod 2^32
        inverse *= 2 - denominator * inverse; // mod 2^64
        inverse *= 2 - denominator * inverse; // mod 2^128
        inverse *= 2 - denominator * inverse; // mod 2^256

        // 最终结果
        result = prod0 * inverse;
        return result;
    }

    /**
     * @dev 计算平方根
     * 使用牛顿-拉夫逊方法逼近平方根
     * @param x 被开方数
     * @return 平方根结果（向下取整）
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 xx = x;
        uint256 r = 1;
        
        // 使用位运算快速找到一个较好的初始估计值
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        
        // 使用牛顿-拉夫逊方法进行7次迭代
        // 公式：x_new = (x + n/x) / 2
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        
        // 选择较小的值作为最终结果（向下取整）
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
}