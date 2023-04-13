// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {CompoundFeeManager} from './CompoundFeeManager.sol';
import {CompoundStratManager} from './CompoundStratManager.sol';

abstract contract CompoundStrat is CompoundStratManager, CompoundFeeManager {
    using SafeERC20 for IERC20;

    address public want;
    address public output;
    address public native;
    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    // EVENTS
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 ethaFees, uint256 strategistFees);

    // Main user interactions
    function deposit() public virtual;

    function withdraw(uint256 _amount) external virtual;

    // Harvest Functions
    function _harvest(address callFeeRecipient) internal virtual;

    function harvestWithCallFeeRecipient(address callFeeRecipient) external virtual whenNotPaused {
        _harvest(callFeeRecipient);
    }

    function harvest() external virtual whenNotPaused {
        _harvest(tx.origin);
    }

    function managerHarvest() external virtual onlyManager {
        _harvest(tx.origin);
    }

    // View Functions

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view virtual returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOfStrategy() public view virtual returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view virtual returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view virtual returns (uint256);

    //Other

    function _giveAllowances() internal virtual;

    function _removeAllowances() internal virtual;

    function pause() public virtual onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external virtual onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function chargeFees(address callFeeRecipient) internal virtual;

    function addLiquidity() internal virtual;

    function retireStrat() external virtual;

    function panic() external virtual;

    function setHarvestOnDeposit(bool _harvestOnDeposit) external virtual onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function beforeDeposit() external virtual onlyVault {
        if (harvestOnDeposit) {
            _harvest(tx.origin);
        }
    }

    function _deductFees(address tokenAddress, address callFeeRecipient, uint256 totalFeeAmount) internal virtual {
        uint256 callFeeAmount;
        uint256 strategistFeeAmount;

        if (callFee > 0) {
            callFeeAmount = (totalFeeAmount * callFee) / MAX_FEE;
            IERC20(tokenAddress).safeTransfer(callFeeRecipient, callFeeAmount);
            emit CallFeeCharged(callFeeRecipient, callFeeAmount);
        }

        if (strategistFee > 0) {
            strategistFeeAmount = (totalFeeAmount * strategistFee) / MAX_FEE;
            IERC20(tokenAddress).safeTransfer(strategist, strategistFeeAmount);
            emit StrategistFeeCharged(strategist, strategistFeeAmount);
        }

        // Send the rest of native tokens remaining to fee recipient
        uint ethaFeeAmt = totalFeeAmount - callFeeAmount - strategistFeeAmount;
        IERC20(tokenAddress).safeTransfer(ethaFeeRecipient, ethaFeeAmt);

        emit ProtocolFeeCharged(ethaFeeRecipient, ethaFeeAmt);
    }
}
