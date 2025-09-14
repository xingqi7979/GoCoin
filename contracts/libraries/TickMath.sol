// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TickMath
 * @dev Tick价格转换数学库 - 处理价格和Tick之间的转换
 * 
 * 核心概念：
 * - Tick：价格的对数表示，便于计算和存储
 * - Price：实际的代币交换比率
 * - SqrtPriceX96：价格平方根的Q64.96定点数表示
 * 
 * 转换关系：
 * price = 1.0001^tick
 * sqrtPriceX96 = sqrt(price) * 2^96
 */
library TickMath {
    /// @dev 支持的最小tick值（对应极小的价格）
    int24 internal constant MIN_TICK = -887272;
    /// @dev 支持的最大tick值（对应极大的价格）
    int24 internal constant MAX_TICK = -MIN_TICK;

    /// @dev 最小价格的平方根值（Q64.96格式）
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev 最大价格的平方根值（Q64.96格式）
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /**
     * @dev 根据tick计算对应的价格平方根
     * 使用泰勒级数展开和位运算优化计算 1.0001^tick 的平方根
     * 
     * 算法原理：
     * 1. 将tick分解为2的幂次的组合
     * 2. 使用预计算的常数进行乘法组合
     * 3. 通过位运算快速计算结果
     * 
     * @param tick 输入的tick值，必须在[MIN_TICK, MAX_TICK]范围内
     * @return sqrtPriceX96 对应的价格平方根（Q64.96格式）
     */
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        // 获取tick的绝对值，用于计算
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        // 验证tick在有效范围内
        require(absTick <= uint256(int256(MAX_TICK)), 'T');

        // 初始化比率，如果tick为奇数则使用特殊常数
        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        
        // 使用位运算检查tick的每一位，如果该位为1，则乘以对应的预计算常数
        // 这些常数是 sqrt(1.0001^(2^i)) * 2^128 的值
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        // 如果原始tick为负数，计算倒数
        if (tick > 0) ratio = type(uint256).max / ratio;

        // 转换为Q64.96格式，向上取整
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /**
     * @dev 根据价格平方根计算对应的tick
     * 使用二分查找和位运算优化的算法
     * 
     * 算法步骤：
     * 1. 验证输入的价格平方根在有效范围内
     * 2. 将sqrtPriceX96左移32位得到ratio
     * 3. 使用位运算找到ratio的最高有效位（MSB）
     * 4. 计算以2为底的对数
     * 5. 转换为以1.0001为底的对数（即tick）
     * 6. 验证结果的准确性
     * 
     * @param sqrtPriceX96 价格平方根（Q64.96格式）
     * @return tick 对应的tick值
     */
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        // 验证价格平方根在有效范围内
        require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO, 'R');
        
        // 左移32位，准备计算对数
        uint256 ratio = uint256(sqrtPriceX96) << 32;

        uint256 r = ratio;
        uint256 msb = 0; // 最高有效位

        // 使用二分查找算法快速找到最高有效位
        // 这一系列assembly块用位运算快速定位MSB
        assembly {
            let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(5, gt(r, 0xFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(4, gt(r, 0xFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(3, gt(r, 0xFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(2, gt(r, 0xF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(1, gt(r, 0x3))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := gt(r, 0x1)
            msb := or(msb, f)
        }

        // 根据MSB调整r的值，使其在[1, 2)范围内
        if (msb >= 128) r = ratio >> (msb - 127);
        else r = ratio << (127 - msb);

        // 初始化log_2的值
        int256 log_2 = (int256(msb) - 128) << 64;

        // 使用泰勒级数计算更精确的对数值
        // 每次迭代增加一位精度
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(63, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(62, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(61, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(60, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(59, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(58, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(57, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(56, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(55, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(54, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(53, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(52, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(51, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(50, f))
        }

        // 将以2为底的对数转换为以sqrt(1.0001)为底的对数
        // 这个常数是 log_2(sqrt(1.0001)) 的Q128表示
        int256 log_sqrt10001 = log_2 * 255738958999603826347141;

        // 计算tick的上下界
        int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
        int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

        // 选择更准确的tick值
        tick = tickLow == tickHi ? tickLow : getSqrtRatioAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow;
    }
}