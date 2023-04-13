//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IQiStrat {
    // Getters
    function priceFeeds(address _token) external view returns (address);

    function balanceOfStrategy() external view returns (uint);

    function balanceOf() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function SAFE_COLLAT_TARGET() external view returns (uint256);

    function SAFE_COLLAT_LOW() external view returns (uint256);

    function SAFE_COLLAT_HIGH() external view returns (uint256);

    function rewardsAvailable() external view returns (uint256);

    function getCollateralPercent() external view returns (uint256 cdr_percent);

    function qiVaultId() external view returns (uint256);

    function getStrategyDebt() external view returns (uint256);

    function safeAmountToBorrow() external view returns (uint256);

    function qiStakingRewards() external view returns (address);

    function lpPairToken() external view returns (address);

    function qiVault() external view returns (address);

    function qiToken() external view returns (address);

    function assetToMai(uint index) external view returns (address);

    function maiToAsset(uint index) external view returns (address);

    function qiToAsset(uint index) external view returns (address);

    function maiToLp0(uint index) external view returns (address);

    function maiToLp1(uint index) external view returns (address);

    function lp0ToMai(uint index) external view returns (address);

    function lp1ToMai(uint index) external view returns (address);

    // Setters
    function setPriceFeed(address _token, address _feed) external;

    function rebalanceVault(bool _shouldRepay) external;

    function harvest() external;

    function repayDebtLp(uint256 _lpAmount) external;
}
