//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../interfaces/common/IUniswapV2Router.sol';
import '../interfaces/common/IUniswapV2Factory.sol';
import './Helpers.sol';

contract SushiswapResolver is Helpers {
    using UniversalERC20 for IERC20;
    using UniversalERC20 for IWETH;

    /**
		@dev This is the address of the router of SushiSwap: SushiV2Router02. 
	**/
    IUniswapV2Router internal constant router = IUniswapV2Router(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    /**
		@dev This is the address of the factory of SushiSwap: SushiV2Factory. 
	**/
    IUniswapV2Factory internal constant factory = IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);

    /** 
		@dev All the events for the router of SushiSwap:
		addLiquidity, removeLiquidity and swap.
	**/

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
	  @dev Swap tokens in SushiSwap Dex with the SushiSwap: SushiV2Router02.
	  @param path Path where the route go from the fromToken to the destToken.
	  @param amountOfTokens Amount of tokens to be swapped, fromToken => destToken.
	  @param getId Read the value of tokenAmt from memory contract, if is needed.
	  @param setId Set value of the tokens swapped in memory contract, if is needed.
		@param divider (for now is always 1).
	**/
    function swap(
        address[] memory path,
        uint256 amountOfTokens,
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 memoryAmount = getId > 0 ? getUint(getId) / divider : amountOfTokens;
        require(memoryAmount > 0, 'SwapTokens: ZERO_AMOUNT');
        require(path.length >= 2, 'SwapTokens: INVALID_PATH');

        /**
			@dev The two tokens, to swap, the path[0] and the path[1].
		**/
        IERC20 fromToken = IERC20(path[0]);
        IERC20 destToken = IERC20(path[path.length - 1]);

        /**
			@dev If the token is the WMATIC then we should first deposit,
			if not then we should only use the universalApprove to approve
			the router to spend the tokens. 
		**/
        if (fromToken.isETH()) {
            wmatic.deposit{value: memoryAmount}();
            wmatic.universalApprove(address(router), memoryAmount);
            path[0] = address(wmatic);
        } else {
            fromToken.universalApprove(address(router), memoryAmount);
        }

        if (destToken.isETH()) {
            path[path.length - 1] = address(wmatic);
        }

        require(path[0] != path[path.length - 1], 'SwapTokens: SAME_ASSETS');

        uint256 received = router.swapExactTokensForTokens(memoryAmount, 1, path, address(this), block.timestamp + 1)[
            path.length - 1
        ];

        uint256 feesPaid = _paySwapFees(destToken, received);

        received = received - feesPaid;

        if (destToken.isETH()) {
            wmatic.withdraw(received);
        }

        if (setId > 0) {
            setUint(setId, received);
        }

        addWithdrawToken(address(fromToken));
        addWithdrawToken(address(destToken));

        emit LogSwap(_msgSender(), address(fromToken), address(destToken), memoryAmount);
    }

    /**
      @dev Add liquidity to Sushiswap pools.
      @param amountA Amount of tokenA to addLiquidity.
      @param amountB Amount of tokenB to addLiquidity.
      @param getId Read the value of the amount of the token from memory contract position 1.
      @param getId2 Read the value of the amount of the token from memory contract position 2.
      @param setId Set value of the LP tokens received in the memory contract.
      @param divider (for now is always 1).
	  **/
    function addLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 getId,
        uint256 getId2,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 realAmtA = getId > 0 ? getUint(getId) / divider : amountA;
        uint256 realAmtB = getId2 > 0 ? getUint(getId2) / divider : amountB;

        require(realAmtA > 0 && realAmtB > 0, 'AddLiquidity: INCORRECT_AMOUNTS');

        IERC20 tokenAReal = tokenA.isETH() ? wmatic : tokenA;
        IERC20 tokenBReal = tokenB.isETH() ? wmatic : tokenB;

        // If either the tokenA or tokenB is WMATIC wrap it.
        if (tokenA.isETH()) {
            wmatic.deposit{value: realAmtA}();
        }
        if (tokenB.isETH()) {
            wmatic.deposit{value: realAmtB}();
        }

        // Approve the router to spend the tokenA and the tokenB.
        tokenAReal.universalApprove(address(router), realAmtA);
        tokenBReal.universalApprove(address(router), realAmtB);

        (, , uint256 liquidity) = router.addLiquidity(
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

        if (setId > 0) {
            setUint(setId, liquidity);
        }

        addWithdrawToken(address(factory.getPair(tokenAReal, tokenBReal)));

        emit LogLiquidityAdd(_msgSender(), address(tokenAReal), address(tokenBReal), amountA, amountB);
    }

    /**
      @dev Remove liquidity from the Sushiswap pool.
      @param tokenA Address of token A from the pool.
      @param tokenA Address of token B from the pool.
      @param amountPoolTokens Amount of the LP tokens to burn. 
      @param getId Read the value from the memory contract. 
      @param setId Set value of the amount of the tokenA received in memory contract position 1.
      @param setId2 Set value of the amount of the tokenB in memory contract position 2.
      @param divider (for now is always 1).
	  **/
    function removeLiquidity(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 amountPoolTokens,
        uint256 getId,
        uint256 setId,
        uint256 setId2,
        uint256 divider
    ) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : amountPoolTokens;

        IERC20 tokenAReal = tokenA.isETH() ? wmatic : tokenA;
        IERC20 tokenBReal = tokenB.isETH() ? wmatic : tokenB;

        // Get the address of the pairPool for the two address of the tokens.
        address poolToken = address(factory.getPair(tokenA, tokenB));

        // Approve the router to spend our LP tokens.
        IERC20(poolToken).universalApprove(address(router), realAmt);

        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenAReal),
            address(tokenBReal),
            realAmt,
            1,
            1,
            address(this),
            block.timestamp + 1
        );

        // Set the tokenA received in the memory contract.
        if (setId > 0) {
            setUint(setId, amountA);
        }

        // Set the tokenB received in the memory contract.
        if (setId2 > 0) {
            setUint(setId2, amountB);
        }

        addWithdrawToken(address(tokenAReal));
        addWithdrawToken(address(tokenBReal));
        addWithdrawToken(poolToken);

        emit LogLiquidityRemove(_msgSender(), address(tokenAReal), address(tokenBReal), amountA, amountB);
    }
}

contract SushiswapLogic is SushiswapResolver {
    string public constant name = 'SushiswapLogic';
    uint8 public constant version = 1;

    /** 
    @dev The fallback function is going to handle
    the Matic sended without any call.
  **/
    receive() external payable {}
}
