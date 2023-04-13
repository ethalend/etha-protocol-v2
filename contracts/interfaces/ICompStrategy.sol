// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ICompStrategy {
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);

    event Deposit(uint256 tvl);

    event Withdraw(uint256 tvl);

    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function callFee() external view returns (uint256);

    function poolId() external view returns (uint256);

    function strategistFee() external view returns (uint256);

    function profitFee() external view returns (uint256);

    function withdrawalFee() external view returns (uint256);

    function MAX_FEE() external view returns (uint256);

    function vault() external view returns (address);

    function want() external view returns (IERC20);

    function outputToNative() external view returns (address[] memory);

    function getStakingContract() external view returns (address);

    function native() external view returns (address);

    function output() external view returns (address);

    function beforeDeposit() external;

    function deposit() external;

    function getMaximumDepositLimit() external view returns (uint256);

    function withdraw(uint256) external;

    function balanceOfStrategy() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function lastHarvest() external view returns (uint256);

    function harvest() external;

    function harvestWithCallFeeRecipient(address) external;

    function retireStrat() external;

    function panic() external;

    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);

    function unirouter() external view returns (address);

    function ethaFeeRecipient() external view returns (address);

    function strategist() external view returns (address);
}
