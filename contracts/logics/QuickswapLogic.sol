//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../interfaces/common/IUniswapV2Router.sol';
import '../interfaces/common/IUniswapV2Exchange.sol';
import '../interfaces/common/IUniswapV2Factory.sol';
import './Helpers.sol';

contract QuickswapResolver is Helpers {
    using UniversalERC20 for IERC20;
    using UniversalERC20 for IWETH;

    IUniswapV2Router internal constant router = IUniswapV2Router(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    IUniswapV2Factory internal constant factory = IUniswapV2Factory(0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32);

    // EVENTS
    event LogSwap(address indexed user, address indexed src, address indexed dest, uint256 amount);
    event LogLiquidityAdd(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB
    );
    event LogLiquidityRemove(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB
    );

    function _paySwapFees(IERC20 erc20, uint256 amt) internal returns (uint256 feesPaid) {
        (uint256 fee, uint256 maxFee, address feeRecipient) = getSwapFee();

        // When swap fee is 0 or sender has partner role
        if (fee == 0) return 0;

        require(feeRecipient != address(0), 'ZERO ADDRESS');

        feesPaid = (amt * fee) / maxFee;
        erc20.universalTransfer(feeRecipient, feesPaid);
    }

    /**
     * @dev Swap tokens in Quickswap dex
     * @param path swap route fromToken => destToken
     * @param tokenAmt amount of fromTokens to swap
     * @param getId read value of tokenAmt from memory contract
     * @param setId set value of tokens swapped in memory contract
     */
    function swap(
        address[] memory path,
        uint256 tokenAmt,
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        require(path.length >= 2, 'INVALID PATH');

        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;
        require(realAmt > 0, 'ZERO AMOUNT');

        IERC20 fromToken = IERC20(path[0]);
        IERC20 destToken = IERC20(path[path.length - 1]);

        if (fromToken.isETH()) {
            wmatic.deposit{value: realAmt}();
            wmatic.universalApprove(address(router), realAmt);
            path[0] = address(wmatic);
        } else fromToken.universalApprove(address(router), realAmt);

        if (destToken.isETH()) path[path.length - 1] = address(wmatic);

        require(path[0] != path[path.length - 1], 'SAME ASSETS');

        uint256 received = router.swapExactTokensForTokens(realAmt, 1, path, address(this), block.timestamp + 1)[
            path.length - 1
        ];

        uint256 feesPaid = _paySwapFees(destToken, received);

        received = received - feesPaid;

        if (destToken.isETH()) {
            wmatic.withdraw(received);
        }

        // set destTokens received
        if (setId > 0) {
            setUint(setId, received);
        }

        addWithdrawToken(address(fromToken));
        addWithdrawToken(address(destToken));

        emit LogSwap(_msgSender(), address(fromToken), address(destToken), realAmt);
    }

    /**
     * @dev Add liquidity to Quickswap pools
     * @param amtA amount of A tokens to add
     * @param amtB amount of B tokens to add
     * @param getId read value of tokenAmt from memory contract position 1
     * @param getId2 read value of tokenAmt from memory contract position 2
     * @param setId set value of LP tokens received in memory contract
     */
    function addLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 amtA,
        uint256 amtB,
        uint256 getId,
        uint256 getId2,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 realAmtA = getId > 0 ? getUint(getId) / divider : amtA;
        uint256 realAmtB = getId2 > 0 ? getUint(getId2) / divider : amtB;

        require(realAmtA > 0 && realAmtB > 0, 'INVALID AMOUNTS');

        IERC20 tokenAReal = tokenA.isETH() ? wmatic : tokenA;
        IERC20 tokenBReal = tokenB.isETH() ? wmatic : tokenB;

        // Wrap Ether
        if (tokenA.isETH()) {
            wmatic.deposit{value: realAmtA}();
        }
        if (tokenB.isETH()) {
            wmatic.deposit{value: realAmtB}();
        }

        // Approve Router
        tokenAReal.universalApprove(address(router), realAmtA);
        tokenBReal.universalApprove(address(router), realAmtB);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenAReal),
            address(tokenBReal),
            realAmtA,
            realAmtB,
            1,
            1,
            address(this),
            block.timestamp + 1
        );

        // send dust amount remaining after liquidity add to user
        _withdrawDust(tokenAReal);
        _withdrawDust(tokenBReal);

        // set aTokens received
        if (setId > 0) {
            setUint(setId, liquidity);
        }

        addWithdrawToken(address(factory.getPair(tokenAReal, tokenBReal)));

        emit LogLiquidityAdd(_msgSender(), address(tokenAReal), address(tokenBReal), amountA, amountB);
    }

    /**
     * @dev Remove liquidity from Quickswap pool
     * @param tokenA address of token A from the pool
     * @param tokenA address of token B from the pool
     * @param poolToken address of the LP token
     * @param amtPoolTokens amount of LP tokens to burn
     * @param getId read value from memory contract
     * @param setId set value of amount tokenB received in memory contract position 1
     * @param setId2 set value of amount tokenB received in memory contract position 2
     */
    function removeLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        IERC20 poolToken,
        uint256 amtPoolTokens,
        uint256 getId,
        uint256 setId,
        uint256 setId2,
        uint256 divider
    ) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : amtPoolTokens;

        IERC20 tokenAReal = tokenA.isETH() ? wmatic : tokenA;
        IERC20 tokenBReal = tokenB.isETH() ? wmatic : tokenB;

        // Approve Router
        IERC20(address(poolToken)).universalApprove(address(router), realAmt);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenAReal),
            address(tokenBReal),
            realAmt,
            1,
            1,
            address(this),
            block.timestamp + 1
        );

        // set tokenA received
        if (setId > 0) {
            setUint(setId, amountA);
        }

        // set tokenA received
        if (setId2 > 0) {
            setUint(setId2, amountB);
        }

        addWithdrawToken(address(tokenAReal));
        addWithdrawToken(address(tokenBReal));
        addWithdrawToken(address(poolToken));

        emit LogLiquidityRemove(_msgSender(), address(tokenAReal), address(tokenBReal), amountA, amountB);
    }
}

contract QuickswapLogic is QuickswapResolver {
    string public constant name = 'QuickswapLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
