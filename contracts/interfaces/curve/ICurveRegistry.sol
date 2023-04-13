// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurverRegisty {
	function find_pool_for_coins(
		address _from,
		address _to,
		uint256 i
	) external view returns (address);

	function get_exchange_amount(
		address _pool,
		address _from,
		address _to,
		uint256 _amount
	) external view returns (uint256);
}
