//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/quickswap/IStakingRewards.sol';
import '../../interfaces/quickswap/IStakingFactory.sol';
import '../../interfaces/joe/IMasterChefJoe.sol';
import '../../interfaces/IERC4626.sol';
import {AvaModifiers, IERC20Metadata, SynthData, ChefData} from './AppStorage.sol';

contract AvaStakingFacet is AvaModifiers {
    /**
        @dev fetch general staking info of a certain synthetix type contract
    */
    function getStakingInfo(
        IStakingFactory stakingFactory,
        address[] calldata poolTokens
    ) external view returns (SynthData[] memory) {
        SynthData[] memory _datas = new SynthData[](poolTokens.length);

        IStakingRewards instance;
        uint256 rewardRate;
        uint256 rewardBalance;
        address rewardsToken;
        uint256 periodFinish;
        uint256 totalStaked;

        for (uint256 i = 0; i < _datas.length; i++) {
            instance = IStakingRewards(stakingFactory.stakingRewardsInfoByStakingToken(poolTokens[i]));

            // If poolToken not present in factory, skip
            if (address(instance) == address(0)) continue;

            rewardsToken = instance.rewardsToken();
            rewardBalance = IERC20Metadata(rewardsToken).balanceOf(address(instance));
            rewardRate = instance.rewardRate();
            periodFinish = instance.periodFinish();
            totalStaked = instance.totalSupply();

            _datas[i] = SynthData(
                poolTokens[i],
                address(instance),
                rewardsToken,
                totalStaked,
                rewardRate,
                periodFinish,
                rewardBalance
            );
        }

        return _datas;
    }

    /**
        @dev fetch reward rate per block for masterchef poolIds
    */
    function getMasterChefInfo(
        IMasterChefJoe chef,
        uint poolId
    ) external view returns (uint ratePerSec, uint totalStaked) {
        uint256 rewardPerSecond = chef.rewardPerSecond();
        (address depositToken, uint allocPoint) = chef.poolInfo(poolId);

        uint256 totalAllocPoint = chef.totalAllocPoint();

        ratePerSec = (rewardPerSecond * allocPoint) / totalAllocPoint;
        totalStaked = IERC20Metadata(depositToken).balanceOf(address(chef));
    }
}
