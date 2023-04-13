//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../interfaces/IVault.sol';
import '../../utils/Timelock.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

abstract contract VolatStrat is Context {
    IVault public vault;
    IERC20 public want;
    IERC20 public output;
    Timelock public timelock;

    // Rewards swap details
    address public unirouter;
    address[] public outputToTargetRoute;

    modifier onlyVault() {
        require(_msgSender() == address(vault), '!vault');
        _;
    }

    modifier onlyTimelock() {
        require(_msgSender() == address(timelock), '!timelock');
        _;
    }

    function invest() external virtual;

    function divest(uint256 amount) external virtual;

    function claim() external virtual returns (uint256 claimed);

    function rescue(address _token, address _to, uint256 _amount) external virtual;

    function setRouter(address router_) external virtual;

    function setSwapRoute(address[] memory outputToTargetRoute_) external virtual;

    function totalYield() external view virtual returns (uint256);

    function calcTotalValue() external view virtual returns (uint256);

    function outputToTarget() external view virtual returns (address[] memory);
}
