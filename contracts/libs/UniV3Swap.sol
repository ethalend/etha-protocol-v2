// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISwapRouter} from '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

library UniV3Swap {
    // Uniswap V3 swap
    function uniV3Swap(address _router, bytes memory _path, uint256 _amount) internal returns (uint256 amountOut) {
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: _path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount,
            amountOutMinimum: 0
        });
        return ISwapRouter(_router).exactInput(swapParams);
    }

    // Uniswap V3 swap with deadline
    function uniV3SwapWithDeadline(
        address _router,
        bytes memory _path,
        uint256 _amount,
        uint deadline
    ) internal returns (uint256 amountOut) {
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: _path,
            recipient: address(this),
            deadline: deadline,
            amountIn: _amount,
            amountOutMinimum: 0
        });
        return ISwapRouter(_router).exactInput(swapParams);
    }
}
