//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract IVGHST is IERC20 {
    function enter(uint256 amount) external virtual returns (uint256);

    function leave(uint256 shares) external virtual;

    function convertVGHST(uint shares) external view virtual returns (uint256 assets);

    function totalGHST(address _user) external view virtual returns (uint256);
}
