// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IeQi {
	function enter(uint256 _amount, uint256 _blockNumber) external;

	function leave() external;

	function endBlock() external view returns (uint256);

	function balanceOf(address user) external view returns (uint256);

	function underlyingBalance(address user) external view returns (uint256);

	function emergencyExit() external;
}
