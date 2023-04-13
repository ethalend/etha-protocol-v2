//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../interfaces/ghst/IVGHST.sol';
import './Helpers.sol';

contract WrapGhstResolver is Helpers {
    using UniversalERC20 for IERC20;

    IVGHST internal constant vGhst = IVGHST(0x51195e21BDaE8722B29919db56d95Ef51FaecA6C);
    IERC20 internal constant Ghst = IERC20(0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7);

    function wrap(uint256 amount, uint getId, uint setId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : amount;

        Ghst.universalApprove(address(vGhst), realAmt);

        uint shares = vGhst.enter(realAmt);

        if (setId > 0) {
            setUint(setId, shares);
        }

        addWithdrawToken(address(vGhst));
    }

    function unwrap(uint256 shares, uint getId, uint setId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : shares;

        uint balBefore = Ghst.balanceOf(address(this));

        vGhst.leave(realAmt);

        if (setId > 0) {
            setUint(setId, Ghst.balanceOf(address(this)) - balBefore);
        }

        addWithdrawToken(address(Ghst));
    }
}

contract WrapGhstLogic is WrapGhstResolver {
    string public constant name = 'WrapGhstLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
