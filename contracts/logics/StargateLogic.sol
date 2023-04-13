//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../interfaces/stargate/IStargateFactory.sol';
import '../interfaces/stargate/IStargatePool.sol';
import '../interfaces/stargate/IStargateRouter.sol';
import './Helpers.sol';

contract StargateResolver is Helpers {
    using UniversalERC20 for IERC20;
    using UniversalERC20 for IWETH;

    IStargateRouter internal constant router = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd);
    IStargateFactory internal constant factory = IStargateFactory(0x808d7c71ad2ba3FA531b068a2417C63106BC0949);

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

    /**
      @dev Add liquidity to Stargate pools.
      @param poolId Stargate Pool ID
      @param amount Amount of token to addLiquidity.
      @param getId Read the value of the amount of the token from memory contract position.
      @param setId Set value of the LP tokens received in the memory contract.
      @param divider (for now is always 1).
	  **/
    function addLiquidity(uint poolId, uint amount, uint256 getId, uint256 setId, uint256 divider) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : amount;
        require(realAmt > 0, 'AddLiquidity: INCORRECT_AMOUNT');

        address pool = factory.getPool(poolId);
        address underlying = IStargatePool(pool).token();

        require(IERC20(underlying).balanceOf(address(this)) >= realAmt, 'AddLiquidity: INSUFFICIENT_BALANCE');

        // Approve the router to spend the token in router
        IERC20(underlying).universalApprove(address(router), realAmt);

        // Execute Liquidity Add
        router.addLiquidity(poolId, realAmt, address(this));

        if (setId > 0) {
            uint liquidity = IERC20(pool).balanceOf(address(this));
            setUint(setId, liquidity);
        }

        addWithdrawToken(pool);
        addWithdrawToken(underlying);

        emit LogLiquidityAdd(_msgSender(), underlying, address(0), amount, 0);
    }

    /**
      @dev Remove liquidity from Stargate pools.
      @param poolId Stargate Pool ID
      @param amount Amount of LP tokens to removeLiquidity.
      @param getId Read the value of the amount of the token from memory contract position.
      @param setId Set value of the LP tokens received in the memory contract.
      @param divider (for now is always 1).
	  **/
    function removeLiquidity(
        uint16 poolId,
        uint amount,
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : amount;
        require(realAmt > 0, 'RemoveLiquidity: INCORRECT_AMOUNT');

        address pool = factory.getPool(poolId);
        address underlying = IStargatePool(pool).token();

        require(IERC20(pool).balanceOf(address(this)) >= realAmt, 'RemoveLiquidity: INSUFFICIENT_BALANCE');

        // Execute Liquidity Remove
        router.instantRedeemLocal(poolId, realAmt, address(this));

        uint received = IERC20(underlying).balanceOf(address(this));

        if (setId > 0) {
            setUint(setId, received);
        }

        addWithdrawToken(pool);
        addWithdrawToken(underlying);

        emit LogLiquidityRemove(_msgSender(), underlying, address(0), received, 0);
    }
}

contract StargateLogic is StargateResolver {
    string public constant name = 'StargateLogic';
    uint8 public constant version = 1;

    /** 
    @dev The fallback function is going to handle
    the Matic sended without any call.
  **/
    receive() external payable {}
}
