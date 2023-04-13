//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Helpers.sol';

contract TransferResolver is Helpers {
    using UniversalERC20 for IERC20;

    event LogDeposit(address indexed user, address indexed erc20, uint256 tokenAmt);
    event LogWithdraw(address indexed user, address indexed erc20, uint256 tokenAmt);

    /**
     * @dev Deposit ERC20 from user
     * @dev user must approve token transfer first
     */
    function deposit(address erc20, uint256 amount, uint getId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : amount;
        require(realAmt > 0, 'ZERO AMOUNT');

        IERC20(erc20).universalTransferFrom(_msgSender(), address(this), realAmt);

        if (erc20 != getAddressETH()) {
            addWithdrawToken(erc20);
        }

        emit LogDeposit(_msgSender(), erc20, realAmt);
    }

    /**
     * @dev Remove ERC20 approval to certain target
     */
    function removeApproval(address erc20, address target) external {
        IERC20(erc20).universalApprove(target, 0);
    }
}

contract TransferLogic is TransferResolver {
    string public constant name = 'TransferLogic';
    uint8 public constant version = 3;
}
