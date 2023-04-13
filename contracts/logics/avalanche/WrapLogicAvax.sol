//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../interfaces/common/IWETH.sol';

contract WrapResolverAvax {
    IWETH internal constant wMatic = IWETH(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    function wrap(uint256 amount) external payable {
        uint256 realAmt = amount == type(uint256).max ? address(this).balance : amount;
        wMatic.deposit{value: realAmt}();
    }

    function unwrap(uint256 amount) external {
        uint256 realAmt = amount == type(uint256).max ? wMatic.balanceOf(address(this)) : amount;
        wMatic.withdraw(realAmt);
    }
}

contract WrapLogicAvax is WrapResolverAvax {
    string public constant name = 'WrapLogicAvax';
    uint8 public constant version = 1;

    receive() external payable {}
}
