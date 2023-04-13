//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libs/UniversalERC20.sol';
import '../interfaces/IERC4626.sol';
import './Helpers.sol';

contract VaultResolverVRC20 is Helpers {
    using UniversalERC20 for IERC20;

    event VaultDeposit(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);
    event VaultWithdraw(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);
    event VaultClaim(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);

    /**
     * @dev Deposit tokens to ETHA Vault
     * @param vault address of vault
     * @param tokenAmt amount of tokens to deposit
     * @param getId read value of tokenAmt from memory contract
     */
    function deposit(IERC4626 vault, uint256 tokenAmt, uint256 getId, uint256 setId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : tokenAmt;

        require(realAmt > 0, '!AMOUNT');

        IERC20 erc20 = IERC20(address(vault.asset()));
        erc20.universalApprove(address(vault), realAmt);

        uint256 sharesBefore = vault.balanceOf(address(this));

        vault.deposit(realAmt, address(this));

        uint sharesAfter = vault.balanceOf(address(this)) - sharesBefore;

        // Store shares received
        if (setId > 0) {
            setUint(setId, sharesAfter);
        }

        // Send vault tokens to user
        IERC20(address(vault)).universalTransfer(_msgSender(), sharesAfter);

        addWithdrawToken(address(erc20));

        emit VaultDeposit(_msgSender(), address(vault), address(erc20), realAmt);
    }

    /**
     * @dev Mints shares and deposit tokens to ETHA Vault
     * @param vault address of vault
     * @param shares amount of vault tokens to mint
     * @param getId read value of tokenAmt from memory contract
     */
    function mint(IERC4626 vault, uint256 shares, uint256 getId, uint256 setId) external payable {
        uint256 realShares = getId > 0 ? getUint(getId) : shares;
        uint256 realAmt = vault.previewMint(realShares);
        require(realShares > 0, '!AMOUNT');

        IERC20 erc20 = IERC20(address(vault.asset()));
        erc20.universalApprove(address(vault), realAmt);

        uint256 sharesBefore = vault.balanceOf(address(this));

        vault.deposit(realAmt, address(this));

        uint sharesAfter = vault.balanceOf(address(this)) - sharesBefore;

        // Store shares received
        if (setId > 0) {
            setUint(setId, sharesAfter);
        }

        // Send vault tokens to user
        IERC20(address(vault)).universalTransfer(_msgSender(), sharesAfter);

        addWithdrawToken(address(erc20));

        emit VaultDeposit(_msgSender(), address(vault), address(erc20), realAmt);
    }

    /**
     * @dev Redeems share tokens from ETHA Vault
     * @param vault address of vault
     * @param shares amount of vault tokens to withdraw
     * @param getId read value of shares to withdraw from memory contract
     * @param getId store amount tokens received in memory contract
     */
    function redeem(IERC4626 vault, uint256 shares, uint256 getId, uint256 setId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : shares;

        require(vault.balanceOf(address(this)) >= realAmt, '!BALANCE');

        address underlying = address(vault.asset());
        uint256 balanceBefore = IERC20(underlying).balanceOf(address(this));

        vault.redeem(realAmt, address(this), address(this));

        uint256 wantReceived = IERC20(underlying).balanceOf(address(this)) - balanceBefore;

        // set tokens received after paying fees
        if (setId > 0) {
            setUint(setId, wantReceived);
        }

        addWithdrawToken(underlying);

        emit VaultWithdraw(_msgSender(), address(vault), underlying, wantReceived);
    }

    /**
     * @dev Redeems share tokens from ETHA Vault
     * @param vault address of vault
     * @param tokenAmt amount of tokens to withdraw
     * @param getId read value of shares to withdraw from memory contract
     * @param getId store amount tokens received in memory contract
     */
    function withdraw(IERC4626 vault, uint256 tokenAmt, uint256 getId, uint256 setId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : tokenAmt;

        require(vault.balanceOf(address(this)) >= realAmt, '!BALANCE');

        address underlying = address(vault.asset());
        uint256 balanceBefore = IERC20(underlying).balanceOf(address(this));

        vault.withdraw(realAmt, address(this), address(this));

        uint256 wantReceived = IERC20(underlying).balanceOf(address(this)) - balanceBefore;

        // set tokens received after paying fees
        if (setId > 0) {
            setUint(setId, wantReceived);
        }

        addWithdrawToken(underlying);

        emit VaultWithdraw(_msgSender(), address(vault), underlying, wantReceived);
    }
}

contract VRC20VaultLogic is VaultResolverVRC20 {
    string public constant name = 'VRC20VaultLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
