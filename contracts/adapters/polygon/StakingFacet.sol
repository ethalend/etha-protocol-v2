//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/quickswap/IStakingRewards.sol';
import '../../interfaces/quickswap/IDragonLair.sol';
import '../../interfaces/quickswap/IStakingFactory.sol';
import '../../interfaces/qiDao/IFarmV3.sol';
import '../../interfaces/IVault.sol';
import '../../interfaces/IERC4626.sol';
import {Modifiers, IERC20Metadata, SynthData, ChefData, DQUICK, QUICK} from './AppStorage.sol';

contract StakingFacet is Modifiers {
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

            // format dQuick to Quick
            if (rewardsToken == DQUICK) {
                rewardRate = IDragonLair(DQUICK).dQUICKForQUICK(instance.rewardRate());
                rewardsToken = QUICK;
                rewardBalance = IDragonLair(DQUICK).dQUICKForQUICK(rewardBalance);
            } else rewardRate = instance.rewardRate();

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
    function getMasterChefInfo(IFarmV3 chef, uint poolId) external view returns (uint ratePerSec, uint totalStaked) {
        uint256 rewardPerSecond = chef.rewardPerSecond();
        (address depositToken, uint allocPoint) = chef.poolInfo(poolId);

        uint256 totalAllocPoint = chef.totalAllocPoint();

        ratePerSec = (rewardPerSecond * allocPoint) / totalAllocPoint;
        totalStaked = IERC20Metadata(depositToken).balanceOf(address(chef));
    }
}
