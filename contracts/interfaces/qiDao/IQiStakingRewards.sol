// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IQiStakingRewards {
    //Public Variables
    function erc20() external view returns (address);

    function totalAllocPoint() external view returns (uint256);

    function rewardPerBlock() external view returns (uint256);

    function endBlock() external view returns (uint256);

    function poolInfo(
        uint256
    )
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accERC20PerShare,
            uint256 depositFeeBP
        );

    function userInfo(uint256 poolId, address user) external view returns (uint256 amount, uint256 rewardDebt);

    // View function to see deposited LP for a user.
    function deposited(uint256 _pid, address _user) external view returns (uint256);

    // Deposit LP tokens to Farm for ERC20 allocation.
    function deposit(uint256 _pid, uint256 _amount) external;

    // Withdraw LP tokens from Farm.
    function withdraw(uint256 _pid, uint256 _amount) external;

    //Pending rewards for an user
    function pending(uint256 _pid, address _user) external view returns (uint256);
}
