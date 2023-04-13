//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libs/UniversalERC20.sol';
import '../interfaces/IVault.sol';
import './Helpers.sol';

contract VaultResolver is Helpers {
    using UniversalERC20 for IERC20;

    event VaultDeposit(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);
    event VaultWithdraw(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);
    event VaultClaim(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);

    /**
     * @dev Deposit tokens to ETHA Vault
     * @param _vault address of vault
     * @param tokenAmt amount of tokens to deposit
     * @param getId read value of tokenAmt from memory contract
     */
    function deposit(IVault _vault, uint256 tokenAmt, uint256 getId, uint setId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : tokenAmt;

        require(realAmt > 0, '!AMOUNT');

        IERC20 erc20 = IERC20(address(_vault.underlying()));
        erc20.universalApprove(address(_vault), realAmt);

        _vault.deposit(realAmt);

        if (setId > 0) {
            setUint(setId, realAmt);
        }

        uint vaultTokensReceived = IERC20(address(_vault)).balanceOf(address(this));

        // Send vault tokens to user
        IERC20(address(_vault)).universalTransfer(_msgSender(), vaultTokensReceived);

        addWithdrawToken(address(erc20));

        emit VaultDeposit(_msgSender(), address(_vault), address(erc20), realAmt);
    }

    /**
     * @dev Withdraw tokens from ETHA Vault
     * @param _vault address of vault
     * @param tokenAmt amount of vault tokens to withdraw
     * @param getId read value of tokenAmt from memory contract
     */
    function withdraw(IVault _vault, uint256 tokenAmt, uint256 getId, uint256 setId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : tokenAmt;

        require(_vault.balanceOf(address(this)) >= realAmt, '!BALANCE');

        address underlying = address(_vault.underlying());

        // Calculate underlying amount received after fees
        uint256 depositBalBefore = IERC20(underlying).balanceOf(address(this));
        _vault.withdraw(realAmt);
        uint256 depositBalAfter = IERC20(underlying).balanceOf(address(this)) - depositBalBefore;

        // set tokens received
        if (setId > 0) {
            setUint(setId, depositBalAfter);
        }

        addWithdrawToken(underlying);
        addWithdrawToken(address(_vault));

        emit VaultWithdraw(_msgSender(), address(_vault), underlying, depositBalAfter);
    }

    /**
     * @dev claim rewards from ETHA Vault
     * @param _vault address of vault
     * @param setId store value of rewards received to memory contract
     */
    function claim(IVault _vault, uint256 setId) external {
        uint256 claimed = _vault.claim();

        // set rewards received
        if (setId > 0) {
            setUint(setId, claimed);
        }

        if (claimed > 0) {
            address target = address(_vault.target());

            addWithdrawToken(target);

            emit VaultClaim(_msgSender(), address(_vault), target, claimed);
        }
    }
}

contract VaultLogic is VaultResolver {
    string public constant name = 'VaultLogic';
    uint8 public constant version = 1;
}
