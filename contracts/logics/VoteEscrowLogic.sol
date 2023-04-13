//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libs/UniversalERC20.sol';
import './Helpers.sol';
import '../interfaces/IVotingEscrow.sol';
import './DSMath.sol';

contract VoteEscrowResolver is DSMath {
    using UniversalERC20 for IERC20;

    event VoteEscrowDeposit(address indexed user, address indexed veETHA, uint256 amountToken, uint256 amtDays);
    event VoteEscrowWithdraw(address indexed user, address indexed veETHA, uint256 amountToken);
    event VoteEscrowIncrease(address indexed user, address indexed veETHA, uint256 amountToken, uint256 amtDays);

    /**
     * @dev Deposit the ETHA tokens to the VoteEscrow contract
     * @param veEthaContract address of VoteEscrow contract.
     * @param tokenAmt amount of tokens to deposit
     * @param noOfDays amount of days to lock.
     * @param getId read value of tokenAmt from memory contract
     */
    function deposit(address veEthaContract, uint256 tokenAmt, uint256 noOfDays, uint256 getId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : tokenAmt;

        require(realAmt > 0, '!AMOUNT');

        address user = _msgSender();

        IVotingEscrow veEtha = IVotingEscrow(veEthaContract);
        IERC20(veEtha.lockedToken()).universalApprove(veEthaContract, realAmt);

        if (veEtha.delegates(user) == address(0)) veEtha.delegate(user);
        veEtha.create_lock(realAmt, noOfDays);

        emit VoteEscrowDeposit(user, veEthaContract, realAmt, noOfDays);
    }

    /**
     * @dev Withdraw tokens from VoteEscrow contract.
     * @param veEthaContract address of veEthaContract.
     */
    function withdraw_unlocked(address veEthaContract) external payable {
        require(veEthaContract != address(0), 'ZERO_ADDRESS');

        IVotingEscrow veEtha = IVotingEscrow(veEthaContract);
        uint prevBal = IERC20(veEtha.lockedToken()).balanceOf(address(this));

        veEtha.withdraw();

        uint withdrawn = IERC20(veEtha.lockedToken()).balanceOf(address(this)) - prevBal;

        emit VoteEscrowWithdraw(_msgSender(), veEthaContract, withdrawn);
    }

    /**
     * @dev Emergency withdraw tokens from VoteEscrow contract.
     * @param veEthaContract address of veEthaContract.
     * @notice This function will collect a fee penalty for withdrawing before time.
     */
    function emergency_withdraw(address veEthaContract) external payable {
        require(veEthaContract != address(0), 'ZERO_ADDRESS');

        IVotingEscrow veEtha = IVotingEscrow(veEthaContract);
        uint prevBal = IERC20(veEtha.lockedToken()).balanceOf(address(this));

        veEtha.emergencyWithdraw();

        uint withdrawn = IERC20(veEtha.lockedToken()).balanceOf(address(this)) - prevBal;

        emit VoteEscrowWithdraw(_msgSender(), veEthaContract, withdrawn);
    }

    /**
     * @dev Increase the amount of ETHA tokens in the VoteEscrow contract
     * @param veEthaContract address of VoteEscrow contract.
     * @param tokenAmt amount of tokens to increment.
     * @param getId read value of tokenAmt from memory contract.
     */
    function increase_amount(address veEthaContract, uint256 tokenAmt, uint256 getId) external payable {
        uint256 realAmt = getId > 0 ? getUint(getId) : tokenAmt;

        require(realAmt > 0, '!AMOUNT');

        IVotingEscrow veEtha = IVotingEscrow(veEthaContract);
        IERC20(veEtha.lockedToken()).universalApprove(veEthaContract, realAmt);

        veEtha.increase_amount(realAmt);

        emit VoteEscrowIncrease(_msgSender(), veEthaContract, realAmt, 0);
    }

    /**
     * @dev Increase the time to be lock the ETHA tokens in the VoteEscrow contract.
     * @param veEthaContract address of VoteEscrowETHA token.
     * @param noOfDays amount of days to increase the lock.
     */
    function increase_time(address veEthaContract, uint256 noOfDays) external payable {
        IVotingEscrow(veEthaContract).increase_unlock_time(noOfDays);

        emit VoteEscrowIncrease(_msgSender(), veEthaContract, 0, noOfDays);
    }
}

contract VoteEscrowLogic is VoteEscrowResolver {
    string public constant name = 'VoteEscrowLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
