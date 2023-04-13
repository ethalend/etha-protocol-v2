//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFarmV3 {
    function balanceOf(address _user) external returns (uint256);

    function getReward(address _user) external;

    function poolLength() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function rewardPerSecond() external view returns (uint256);

    function fund(uint256 _amount) external;

    function deposited(uint256 _pid, address _user) external view returns (uint256);

    function pending(uint256 _pid, address _user) external view returns (uint256);

    function totalPending() external view returns (uint256);

    function massUpdatePools() external;

    function updatePool(uint256 _pid) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint _pid, uint256 _amount) external;

    function poolInfo(uint _pid) external view returns (address lpToken, uint allocPoint);
}
