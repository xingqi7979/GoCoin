// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IPool.sol";
import "./interfaces/ICallback.sol";
import "./PoolManager.sol";
import "./libraries/Math.sol";
import "./libraries/TickMath.sol";

/**
 * @title PositionManager
 * @dev 头寸管理合约 - 将流动性头寸表示为NFT进行管理
 * 
 * 核心特性：
 * - ERC721标准：每个流动性头寸都是一个独特的NFT
 * - 代理模式：作为用户和Pool合约之间的中介
 * - 头寸管理：创建、查询、销毁流动性头寸
 * - 手续费收取：管理用户的手续费收入
 * - 权限控制：只有NFT所有者可以操作对应头寸
 * 
 * 设计优势：
 * - 可转让性：NFT可以在用户之间转让
 * - 可组合性：可以与其他DeFi协议集成
 * - 可视化：每个头寸都有唯一的tokenId
 * - 标准化：遵循ERC721标准，兼容性好
 */
contract PositionManager is ERC721, IMintCallback {
    using SafeERC20 for IERC20;

    // ============ 头寸信息结构 ============
    
    /**
     * @dev 头寸详细信息结构
     * 记录每个NFT头寸的完整状态信息
     */
    struct PositionInfo {
        address owner;        // 头寸所有者地址
        address token0;       // 第一个代币地址
        address token1;       // 第二个代币地址
        uint32 index;         // 池子索引
        uint24 fee;           // 手续费率
        uint128 liquidity;    // 头寸包含的流动性数量
        int24 tickLower;      // 价格区间下限
        int24 tickUpper;      // 价格区间上限
    }

    /**
     * @dev 创建头寸的参数结构
     */
    struct MintParams {
        address token0;          // 第一个代币地址
        address token1;          // 第二个代币地址
        uint32 index;            // 目标池子的索引
        uint256 amount0Desired;  // 期望投入的token0数量
        uint256 amount1Desired;  // 期望投入的token1数量
        address recipient;       // NFT接收者地址
        uint256 deadline;        // 交易截止时间
    }

    // ============ 状态变量 ============
    
    /// @dev 池管理器合约实例，用于获取池子信息
    PoolManager public immutable poolManager;
    
    /// @dev NFT序号计数器，从1开始（0保留为无效值）
    uint256 private _nextId = 1;

    /// @dev 头寸ID到头寸信息的映射
    mapping(uint256 => PositionInfo) private _positions;

    /**
     * @dev 交易截止时间检查修饰器
     * 确保交易在指定时间前完成，防止过期交易执行
     * @param deadline 截止时间戳（Unix时间）
     */
    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "EXPIRED");
        _;
    }

    /**
     * @dev 构造函数 - 初始化ERC721合约和池管理器引用
     * @param _poolManager 池管理器合约地址
     */
    constructor(address _poolManager) ERC721("MetaNodeSwap Position", "MNS-POS") {
        poolManager = PoolManager(_poolManager);
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        checkDeadline(params.deadline) // 检查交易截止时间
        returns (
            uint256 positionId, // 返回新创建的头寸ID
            uint128 liquidity,  // 返回实际添加的流动性数量
            uint256 amount0,    // 返回实际消耗的token0数量
            uint256 amount1     // 返回实际消耗的token1数量
        )
    {
        // 获取目标池子的地址
        address poolAddress = poolManager.getPoolAddress(params.index);
        require(poolAddress != address(0), "POOL_NOT_EXISTS"); // 确保池子存在

        // 创建池子合约实例
        IPool pool = IPool(poolAddress);
        // 验证代币地址是否匹配池子中的代币
        require(pool.token0() == params.token0 && pool.token1() == params.token1, "INVALID_TOKENS");

        // 根据当前价格和期望数量计算实际需要的流动性
        liquidity = computeLiquidityFromAmounts(
            pool.sqrtPriceX96(),      // 当前价格的平方根
            pool.tickLower(),         // 价格区间下限
            pool.tickUpper(),         // 价格区间上限
            params.amount0Desired,    // 期望的token0数量
            params.amount1Desired     // 期望的token1数量
        );

        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY"); // 确保计算出的流动性大于0

        // 生成新的头寸ID并铸造NFT
        positionId = _nextId++; // 递增计数器获取新ID
        _mint(params.recipient, positionId); // 向接收者铸造NFT

        // 向池子添加流动性
        (amount0, amount1) = pool.mint(
            address(this), // 流动性接收者为当前合约
            liquidity,     // 要添加的流动性数量
            abi.encode(MintCallbackData({ // 编码回调数据
                token0: params.token0,
                token1: params.token1,
                amount0: params.amount0Desired,
                amount1: params.amount1Desired,
                payer: msg.sender // 付款方为调用者
            }))
        );

        // 存储头寸信息到映射中
        _positions[positionId] = PositionInfo({
            owner: params.recipient,     // 头寸所有者
            token0: params.token0,       // 第一个代币
            token1: params.token1,       // 第二个代币
            index: params.index,         // 池子索引
            fee: pool.fee(),            // 手续费率
            liquidity: liquidity,        // 流动性数量
            tickLower: pool.tickLower(), // 价格区间下限
            tickUpper: pool.tickUpper()  // 价格区间上限
        });
    }

    /**
     * @dev 销毁头寸并移除流动性
     * 只有NFT的所有者或被授权者可以调用此函数
     * 
     * @param positionId 要销毁的头寸ID
     * @return amount0 可提取的token0数量
     * @return amount1 可提取的token1数量
     */
    function burn(
        uint256 positionId
    ) external returns (uint256 amount0, uint256 amount1) {
        // 检查调用者是否有权限操作此头寸
        require(_isAuthorized(ownerOf(positionId), msg.sender, positionId), "NOT_AUTHORIZED");

        // 获取头寸信息的存储引用
        PositionInfo storage position = _positions[positionId];
        require(position.liquidity > 0, "INVALID_POSITION"); // 确保头寸有效且有流动性

        // 获取对应的池子合约
        address poolAddress = poolManager.getPoolAddress(position.index);
        IPool pool = IPool(poolAddress);

        // 从池子中移除流动性（这会将代币添加到Pool的tokensOwed中）
        (amount0, amount1) = pool.burn(position.liquidity);

        // 从池子中收取所有待提取的代币（包括刚移除的流动性和之前累积的手续费）
        (uint128 collectAmount0, uint128 collectAmount1) = pool.collect(msg.sender);

        // 返回实际收取的数量
        amount0 = uint256(collectAmount0);
        amount1 = uint256(collectAmount1);

        // 清理头寸数据
        position.liquidity = 0;

        // 销毁对应的NFT
        _burn(positionId);
    }

    /**
     * @dev 收取头寸累积的手续费和代币
     * 包括移除流动性获得的代币和交易手续费收入
     * 
     * @param positionId 头寸ID
     * @param recipient 代币接收者地址
     * @return amount0 实际收取的token0数量
     * @return amount1 实际收取的token1数量
     */
    function collect(
        uint256 positionId,
        address recipient
    ) external returns (uint256 amount0, uint256 amount1) {
        // 检查调用者是否有权限操作此头寸
        require(_isAuthorized(ownerOf(positionId), msg.sender, positionId), "NOT_AUTHORIZED");

        // 获取头寸信息的存储引用
        PositionInfo storage position = _positions[positionId];
        
        // 获取对应的池子合约
        address poolAddress = poolManager.getPoolAddress(position.index);
        IPool pool = IPool(poolAddress);

        // 从池子收取累积的手续费
        (uint128 collectAmount0, uint128 collectAmount1) = pool.collect(recipient);

        // 返回实际收取的数量
        amount0 = uint256(collectAmount0);
        amount1 = uint256(collectAmount1);
    }

    /**
     * @dev 获取头寸的详细信息
     * @param positionId 头寸ID
     * @return positionInfo 头寸的完整信息
     */
    function getPositionInfo(
        uint256 positionId
    ) external view returns (PositionInfo memory positionInfo) {
        return _positions[positionId]; // 返回存储的头寸信息
    }

    /**
     * @dev 铸造流动性回调数据结构
     * 用于在mintCallback函数中传递必要信息
     */
    struct MintCallbackData {
        address token0;   // 第一个代币地址
        address token1;   // 第二个代币地址
        uint256 amount0;  // 期望的token0数量
        uint256 amount1;  // 期望的token1数量
        address payer;    // 付款方地址
    }

    /**
     * @dev 铸造流动性回调函数
     * 当Pool合约执行mint时会调用此函数来获取所需的代币
     * 
     * @param amount0Owed 需要支付的token0数量
     * @param amount1Owed 需要支付的token1数量
     * @param data 编码的回调数据
     */
    function mintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        // 解码回调数据
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        // 转入所需的token0（如果需要的话）
        if (amount0Owed > 0) {
            IERC20(decoded.token0).safeTransferFrom(decoded.payer, msg.sender, amount0Owed);
        }
        // 转入所需的token1（如果需要的话）
        if (amount1Owed > 0) {
            IERC20(decoded.token1).safeTransferFrom(decoded.payer, msg.sender, amount1Owed);
        }
    }

    /**
     * @dev 根据代币数量计算流动性
     * 这是Uniswap V3的核心算法，用于将代币数量转换为流动性单位
     * 
     * @param sqrtPriceX96 当前价格的平方根（Q64.96格式）
     * @param tickLower 价格区间下限对应的tick
     * @param tickUpper 价格区间上限对应的tick
     * @param amount0 期望投入的token0数量
     * @param amount1 期望投入的token1数量
     * @return liquidity 计算出的流动性数量
     */
    function computeLiquidityFromAmounts(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        // 如果两种代币数量都为0，返回0流动性
        if (amount0 == 0 && amount1 == 0) return 0;
        
        // 将tick转换为对应的价格平方根
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower); // 区间下限价格
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper); // 区间上限价格
        
        // 根据当前价格相对于价格区间的位置，采用不同的计算方法
        if (sqrtPriceX96 <= sqrtRatioAX96) {
            // 当前价格低于区间下限：只需要token0
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtPriceX96 < sqrtRatioBX96) {
            // 当前价格在区间内：需要两种代币，取较小的流动性值
            uint128 liquidity0 = getLiquidityForAmount0(sqrtPriceX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, amount1);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            // 当前价格高于区间上限：只需要token1
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /**
     * @dev 根据token0数量计算流动性
     * 用于当前价格低于或在价格区间内的情况
     * 
     * @param sqrtRatioAX96 较低价格的平方根
     * @param sqrtRatioBX96 较高价格的平方根  
     * @param amount0 token0的数量
     * @return liquidity 对应的流动性数量
     */
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        // 确保价格顺序正确
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        
        // 使用公式：L = amount0 * (sqrtRatioA * sqrtRatioB) / (sqrtRatioB - sqrtRatioA)
        uint256 intermediate = Math.mulDiv(sqrtRatioAX96, sqrtRatioBX96, 1 << 96);
        return uint128(Math.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /**
     * @dev 根据token1数量计算流动性
     * 用于当前价格高于或在价格区间内的情况
     * 
     * @param sqrtRatioAX96 较低价格的平方根
     * @param sqrtRatioBX96 较高价格的平方根
     * @param amount1 token1的数量
     * @return liquidity 对应的流动性数量
     */
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        // 确保价格顺序正确
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        
        // 使用公式：L = amount1 / (sqrtRatioB - sqrtRatioA) * 2^96
        return uint128(Math.mulDiv(amount1, 1 << 96, sqrtRatioBX96 - sqrtRatioAX96));
    }
}