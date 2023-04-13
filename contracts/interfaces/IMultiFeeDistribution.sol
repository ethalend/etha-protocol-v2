// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMultiFeeDistribution {
    struct Reward {
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        // tracks already-added balances to handle accrued interest in aToken rewards
        // for the stakingToken this value is unused and will always be 0
        uint256 balance;
    }

    struct RewardData {
        address token;
        uint256 amount;
    }

    function stake(uint256 amount, address user) external;

    function withdraw(uint256 amount, address user) external;

    function getReward(address[] memory _rewardTokens, address user) external;

    function exit(address user) external;

    function getRewardTokens() external view returns (address[] memory);

    function rewardData(address) external view returns (Reward memory);

    function claimableRewards(address) external view returns (RewardData[] memory);

    function totalStaked() external view returns (uint);

    function balances(address) external view returns (uint);
}
