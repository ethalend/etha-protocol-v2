// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAaveRewardsController {
    function getUserRewards(
        address[] calldata assets,
        address user,
        address reward
    ) external view returns (uint256);

    function getAllUserRewards(address[] calldata assets, address user)
        external
        view
        returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts);

    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to,
        address reward
    ) external returns (uint256);

    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
