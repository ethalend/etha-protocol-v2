//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

interface IVault {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function claim() external returns (uint256 claimed);

    function harvest() external returns (uint256);

    function distribute(uint256 amount) external;

    function totalSupply() external view returns (uint256);

    function claimOnBehalf(address recipient) external;

    function rewards() external view returns (IERC20);

    function underlying() external view returns (IERC20Metadata);

    function target() external view returns (IERC20);

    function harvester() external view returns (address);

    function owner() external view returns (address);

    function strat() external view returns (address);

    function timelock() external view returns (address payable);

    function feeRecipient() external view returns (address);

    function lastDistribution() external view returns (uint256);

    function MAX_FEE() external view returns (uint256);

    function performanceFee() external view returns (uint256);

    function profitFee() external view returns (uint256);

    function withdrawalFee() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function totalYield() external returns (uint256);

    function calcTotalValue() external view returns (uint256);

    function unclaimedProfit(address user) external view returns (uint256);

    function pending(address user) external view returns (uint256);

    function name() external view returns (string memory);
}
