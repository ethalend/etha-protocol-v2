//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Helpers.sol';

contract WrapResolver is Helpers {
    function wrap(uint256 amount) external payable {
        uint256 realAmt = amount == type(uint256).max ? address(this).balance : amount;
        wmatic.deposit{value: realAmt}();

        addWithdrawToken(address(wmatic));
    }

    function unwrap(uint256 amount) external {
        uint256 realAmt = amount == type(uint256).max ? wmatic.balanceOf(address(this)) : amount;
        wmatic.withdraw(realAmt);
    }
}

contract WrapLogic is WrapResolver {
    string public constant name = 'WrapLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
