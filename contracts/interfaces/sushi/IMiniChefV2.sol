// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ISushiRewarder.sol";

interface IMiniChefV2 {
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, ISushiRewarder indexed rewarder);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, ISushiRewarder indexed rewarder, bool overwrite);
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 lpSupply, uint256 accSushiPerShare);
    event LogSushiPerSecond(uint256 sushiPerSecond);

    function poolLength() external view returns (uint256);

    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);

    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function harvest(uint256 pid, address to) external;

    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function emergencyWithdraw(uint256 pid, address to) external;

    function rewarder(uint256 pid) external view returns (address);
}
