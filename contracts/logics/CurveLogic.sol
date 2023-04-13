//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libs/UniversalERC20.sol';
import '../interfaces/curve/ICurvePool.sol';
import '../interfaces/IAdapter.sol';
import './Helpers.sol';

contract CurveResolver is Helpers {
    using UniversalERC20 for IERC20;

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

    function toInt128(uint256 num) internal pure returns (int128) {
        return int128(int256(num));
    }

    function _paySwapFees(IERC20 erc20, uint256 amt) internal returns (uint256 feesPaid) {
        (uint256 fee, uint256 maxFee, address feeRecipient) = getSwapFee();

        // When swap fee is 0 or sender has partner role
        if (fee == 0) return 0;

        require(feeRecipient != address(0), 'ZERO ADDRESS');

        feesPaid = (amt * fee) / maxFee;
        erc20.universalTransfer(feeRecipient, feesPaid);
    }

    /**
     * @notice swap tokens in curve pool
     * @param getId read value from memory contract
     * @param setId set dest tokens received to memory contract
     */
    function swap(
        ICurvePool pool,
        address src,
        address dest,
        uint256 tokenAmt,
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        uint256 i;
        uint256 j;

        for (uint256 x = 1; x <= 3; x++) {
            if (pool.underlying_coins(x - 1) == src) i = x;
            if (pool.underlying_coins(x - 1) == dest) j = x;
        }

        require(i != 0 && j != 0);

        IERC20(src).universalApprove(address(pool), realAmt);

        uint256 received = pool.exchange_underlying(toInt128(i - 1), toInt128(j - 1), realAmt, 0);

        uint256 feesPaid = _paySwapFees(IERC20(dest), received);

        received = received - feesPaid;

        // set j tokens received
        if (setId > 0) {
            setUint(setId, received);
        }

        addWithdrawToken(src);
        addWithdrawToken(dest);

        emit LogSwap(_msgSender(), src, dest, realAmt);
    }

    /**
     * @notice add liquidity to Curve Pool
     * @param tokenId id of the token to remove liq. Should be 0, 1 or 2
     * @param getId read value from memory contract
     * @param setId set LP tokens received to memory contract
     */
    function addLiquidity(
        address lpToken,
        uint256 tokenAmt,
        uint256 tokenId, // 0, 1 or 2
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        address token;

        ICurvePool pool = ICurvePool(IAdapter(getAdapterAddress()).getCurvePool(lpToken));

        try pool.underlying_coins(tokenId) returns (address _token) {
            token = _token;
        } catch {
            revert('!TOKENID');
        }

        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        uint256[3] memory tokenAmts;
        tokenAmts[tokenId] = realAmt;

        IERC20(token).universalApprove(address(pool), realAmt);

        uint256 liquidity = pool.add_liquidity(tokenAmts, 0, true);

        // set LP tokens received
        if (setId > 0) {
            setUint(setId, liquidity);
        }

        addWithdrawToken(lpToken);

        emit LogLiquidityAdd(_msgSender(), token, address(0), realAmt, 0);
    }

    /**
     * @notice add liquidity to Curve Pool
     * @param tokenId id of the token to remove liq. Should be 0, 1 or 2
     * @param getId read value from memory contract
     * @param setId set LP tokens received to memory contract
     */
    function addLiquidity2(
        address lpToken,
        uint256 tokenAmt,
        uint256 tokenId, // 0 or 1
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        address token;

        ICurvePool pool = ICurvePool(IAdapter(getAdapterAddress()).getCurvePool(lpToken));

        try pool.coins(tokenId) returns (address _token) {
            token = _token;
        } catch {
            revert('!TOKENID');
        }

        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        uint256[2] memory tokenAmts;
        tokenAmts[tokenId] = realAmt;

        IERC20(token).universalApprove(address(pool), realAmt);

        uint256 liquidity = pool.add_liquidity(tokenAmts, 0, false);

        // set LP tokens received
        if (setId > 0) {
            setUint(setId, liquidity);
        }

        addWithdrawToken(lpToken);

        emit LogLiquidityAdd(_msgSender(), token, address(0), realAmt, 0);
    }

    /**
     * @notice remove liquidity from Curve Pool
     * @param tokenAmt amount of pool Tokens to burn
     * @param tokenId id of the token to remove liq. Should be 0, 1 or 2
     * @param getId read value of amount from memory contract
     * @param setId set value of tokens received in memory contract
     */
    function removeLiquidity(
        address lpToken,
        uint256 tokenAmt,
        uint256 tokenId,
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        require(realAmt > 0, 'ZERO AMOUNT');
        require(tokenId <= 2, 'INVALID TOKEN');

        address pool = IAdapter(getAdapterAddress()).getCurvePool(lpToken);

        IERC20(lpToken).universalApprove(pool, realAmt);

        uint256 amountReceived = ICurvePool(pool).remove_liquidity_one_coin(realAmt, int128(int256(tokenId)), 1, true);

        // set tokens received
        if (setId > 0) {
            setUint(setId, amountReceived);
        }

        address _token = ICurvePool(pool).underlying_coins(tokenId);

        addWithdrawToken(_token);

        emit LogLiquidityRemove(_msgSender(), _token, address(0), amountReceived, 0);
    }

    /**
     * @notice remove liquidity from Curve Pool
     * @param tokenAmt amount of pool Tokens to burn
     * @param tokenId id of the token to remove liq. Should be 0 or 1
     * @param getId read value of amount from memory contract
     * @param setId set value of tokens received in memory contract
     */
    function removeLiquidity2(
        address lpToken,
        uint256 tokenAmt,
        uint256 tokenId,
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        require(realAmt > 0, 'ZERO AMOUNT');
        require(tokenId <= 1, 'INVALID TOKEN');

        address pool = IAdapter(getAdapterAddress()).getCurvePool(lpToken);

        IERC20(lpToken).universalApprove(pool, realAmt);

        uint256 amountReceived = ICurvePool(pool).remove_liquidity_one_coin(realAmt, tokenId, 1, false);

        // set tokens received
        if (setId > 0) {
            setUint(setId, amountReceived);
        }

        address _token = ICurvePool(pool).coins(tokenId);

        addWithdrawToken(_token);

        emit LogLiquidityRemove(_msgSender(), _token, address(0), amountReceived, 0);
    }
}

contract CurveLogic is CurveResolver {
    string public constant name = 'CurveLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
