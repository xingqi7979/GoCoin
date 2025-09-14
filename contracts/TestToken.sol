// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TestToken
 * @dev 测试用的ERC20代币合约
 * 继承自OpenZeppelin的标准ERC20实现，主要用于测试和演示
 * 包含铸币功能，方便在测试环境中分发代币
 */
contract TestToken is ERC20 {
    /**
     * @dev 构造函数 - 创建代币并铸造初始供应量给部署者
     * @param name 代币名称（如"Token A"）
     * @param symbol 代币符号（如"TKA"）
     * @param supply 初始供应量（不包含小数位，实际铸造量会乘以10^decimals()）
     */
    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        // 铸造初始供应量给合约部署者
        // supply会自动乘以10^decimals()得到实际的token数量
        _mint(msg.sender, supply * 10**decimals());
    }

    /**
     * @dev 铸造代币给指定地址
     * 这是一个公开函数，任何人都可以调用（仅用于测试环境）
     * 在生产环境中，这个函数应该有适当的访问控制
     * @param to 接收代币的地址
     * @param amount 铸造的代币数量
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}