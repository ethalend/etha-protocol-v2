//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/IVotingEscrow.sol';
import '../../interfaces/IMultiFeeDistribution.sol';
import '../../interfaces/common/IUniswapV2Router.sol';
import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import {Modifiers, VeEthaInfo, Rewards, MATIC, IERC20, WMATIC} from './AppStorage.sol';

contract GettersFacet is Modifiers {
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;

    function getTokenFeed(address token) external view returns (address) {
        return s.priceFeeds[token];
    }

    function getPrice(address token) external view returns (int256) {
        address feed = s.priceFeeds[token];

        if (feed != address(0)) {
            (, int256 price, , , ) = AggregatorV3Interface(feed).latestRoundData();
            return price;
        } else return 0;
    }

    function getPriceQuickswap(address token, uint amount) external view returns (uint256) {
        address[] memory path;
        path[0] = token;
        path[1] = USDC;
        uint received = IUniswapV2Router(ROUTER).getAmountsOut(amount, path)[1];

        path[1] = WMATIC;
        path[2] = USDC;
        uint received2 = IUniswapV2Router(ROUTER).getAmountsOut(amount, path)[2];

        uint bestPrice = received > received2 ? received : received2;

        return formatDecimals(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, bestPrice);
    }

    function getAToken(address token) external view returns (address) {
        return s.aTokens[token];
    }

    function getCrToken(address token) external view returns (address) {
        return s.crTokens[token];
    }

    function getCurvePool(address token) external view returns (address) {
        return s.curvePools[token];
    }

    function getBalances(address[] calldata tokens, address user) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == MATIC) balances[i] = user.balance;
            else balances[i] = IERC20(tokens[i]).balanceOf(user);
        }

        return balances;
    }

    function getGovernanceInfo(
        address veETHA,
        address user
    ) external view returns (VeEthaInfo memory info, Rewards[] memory rewards) {
        info.feeRecipient = IVotingEscrow(veETHA).penaltyCollector();
        info.minLockedAmount = IVotingEscrow(veETHA).minLockedAmount();
        info.penaltyRate = IVotingEscrow(veETHA).earlyWithdrawPenaltyRate();
        info.totalEthaLocked = IVotingEscrow(veETHA).supply();
        info.totalVeEthaSupply = IVotingEscrow(veETHA).totalSupply();
        info.userVeEthaBalance = IVotingEscrow(veETHA).balanceOf(user);
        (info.userEthaLocked, info.userLockEnds) = IVotingEscrow(veETHA).locked(user);

        info.multiFeeAddress = IVotingEscrow(veETHA).multiFeeDistribution();
        IMultiFeeDistribution multiFee = IMultiFeeDistribution(info.multiFeeAddress);
        info.multiFeeTotalStaked = multiFee.totalStaked();
        info.multiFeeUserStake = multiFee.balances(user);

        address[] memory rewardTokens = multiFee.getRewardTokens(); // only works with new multi fee

        IMultiFeeDistribution.RewardData[] memory userClaimable = multiFee.claimableRewards(user);
        rewards = new Rewards[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IMultiFeeDistribution.Reward memory rewardData = multiFee.rewardData(rewardTokens[i]);
            rewards[i].tokenAddress = rewardTokens[i];
            rewards[i].rewardRate = rewardData.rewardRate;
            rewards[i].periodFinish = rewardData.periodFinish;
            rewards[i].balance = rewardData.balance;
            rewards[i].claimable = userClaimable[i].amount;
        }
    }
}
