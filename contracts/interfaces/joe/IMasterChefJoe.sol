// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMasterChefJoe {
    function JOE() external view returns (address);

    function rewardPerSecond() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

    function emergencyWithdraw(uint256 _pid) external;

    function pendingTokens(
        uint256 _pid,
        address _user
    ) external view returns (uint256, address, string memory, uint256);

    function poolInfo(uint256 poolId) external view returns (address lpToken, uint allocPoint);

    //Pending rewards for an user
    function pending(uint256 _pid, address _user) external view returns (uint256);
}
