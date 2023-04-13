//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../interfaces/aave/ILendingPool.sol';
import '../interfaces/aave/IAaveAddressProvider.sol';
import '../interfaces/aave/IAToken.sol';
import '../interfaces/IAdapter.sol';
import '../libs/UniversalERC20.sol';
import './Helpers.sol';

contract AaveHelpers is Helpers {
    using UniversalERC20 for IERC20;

    /**
     * @dev get Aave Lending Pool Address V2
     */
    function getLendingPoolAddress() public view returns (address lendingPoolAddress) {
        IAaveAddressProvider adr = IAaveAddressProvider(0xd05e3E715d945B59290df0ae8eF85c1BdB684744);
        return adr.getLendingPool();
    }

    function getReferralCode() public pure returns (uint16) {
        return uint16(0);
    }
}

contract AaveResolver is AaveHelpers {
    using UniversalERC20 for IERC20;

    event LogMint(address indexed erc20, uint256 tokenAmt);
    event LogRedeem(address indexed erc20, uint256 tokenAmt);
    event LogBorrow(address indexed erc20, uint256 tokenAmt);
    event LogPayback(address indexed erc20, uint256 tokenAmt);

    /**
     * @dev Deposit MATIC/ERC20 and mint Aave V2 Tokens
     * @param erc20 underlying asset to deposit
     * @param tokenAmt amount of underlying asset to deposit
     * @param getId read value of tokenAmt from memory contract
     * @param setId set value of aTokens minted in memory contract
     */
    function mintAToken(
        address erc20,
        uint256 tokenAmt,
        uint256 getId,
        uint256 setId,
        uint256 divider
    ) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        address aToken = IAdapter(getAdapterAddress()).getAToken(erc20);
        uint256 initialBal = IERC20(aToken).universalBalanceOf(address(this));

        require(aToken != address(0), 'INVALID ASSET');

        require(realAmt > 0 && realAmt <= IERC20(erc20).universalBalanceOf(address(this)), 'INVALID AMOUNT');

        address realToken = erc20;

        if (erc20 == getAddressETH()) {
            wmatic.deposit{value: realAmt}();
            realToken = address(wmatic);
        }

        ILendingPool _lendingPool = ILendingPool(getLendingPoolAddress());

        IERC20(realToken).universalApprove(address(_lendingPool), realAmt);

        _lendingPool.deposit(realToken, realAmt, address(this), getReferralCode());

        // set aTokens received
        if (setId > 0) {
            setUint(setId, IERC20(aToken).universalBalanceOf(address(this)) - initialBal);
        }

        emit LogMint(erc20, realAmt);
    }

    /**
     * @dev Redeem MATIC/ERC20 and burn Aave V2 Tokens
     * @param erc20 underlying asset to redeem
     * @param tokenAmt Amount of underling tokens
     * @param getId read value of tokenAmt from memory contract
     * @param setId set value of tokens redeemed in memory contract
     */
    function redeemAToken(address erc20, uint256 tokenAmt, uint256 getId, uint256 setId, uint256 divider) external {
        IAToken aToken = IAToken(IAdapter(getAdapterAddress()).getAToken(erc20));
        require(address(aToken) != address(0), 'INVALID ASSET');

        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        require(realAmt > 0, 'ZERO AMOUNT');
        require(realAmt <= aToken.balanceOf(address(this)), 'INVALID AMOUNT');

        ILendingPool _lendingPool = ILendingPool(getLendingPoolAddress());
        _lendingPool.withdraw(erc20, realAmt, address(this));

        // set amount of tokens received minus fees
        if (setId > 0) {
            setUint(setId, realAmt);
        }

        emit LogRedeem(erc20, realAmt);
    }

    /**
     * @dev Redeem MATIC/ERC20 and burn Aave Tokens
     * @param erc20 Address of the underlying token to borrow
     * @param tokenAmt Amount of underlying tokens to borrow
     * @param getId read value of tokenAmt from memory contract
     * @param setId set value of tokens borrowed in memory contract
     */
    function borrow(address erc20, uint256 tokenAmt, uint256 getId, uint256 setId, uint256 divider) external payable {
        address realToken = erc20 == getAddressETH() ? address(wmatic) : erc20;

        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        ILendingPool(getLendingPoolAddress()).borrow(realToken, realAmt, 2, getReferralCode(), address(this));

        // set amount of tokens received
        if (setId > 0) {
            setUint(setId, realAmt);
        }

        emit LogBorrow(erc20, realAmt);
    }

    /**
     * @dev Redeem MATIC/ERC20 and burn Aave Tokens
     * @param erc20 Address of the underlying token to repay
     * @param tokenAmt Amount of underlying tokens to repay
     * @param getId read value of tokenAmt from memory contract
     * @param setId set value of tokens repayed in memory contract
     */
    function repay(address erc20, uint256 tokenAmt, uint256 getId, uint256 setId, uint256 divider) external payable {
        address realToken = erc20;

        uint256 realAmt = getId > 0 ? getUint(getId) / divider : tokenAmt;

        if (erc20 == getAddressETH()) {
            wmatic.deposit{value: realAmt}();
            realToken = address(wmatic);
        }

        IERC20(realToken).universalApprove(getLendingPoolAddress(), realAmt);

        ILendingPool(getLendingPoolAddress()).repay(realToken, realAmt, 2, address(this));

        // set amount of tokens received
        if (setId > 0) {
            setUint(setId, realAmt);
        }

        emit LogPayback(erc20, realAmt);
    }
}

contract AaveLogic is AaveResolver {
    string public constant name = 'AaveLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
