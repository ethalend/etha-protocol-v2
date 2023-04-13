// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {LibDiamond} from '../../libs/LibDiamond.sol';
import {LibMeta} from '../../libs/LibMeta.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

address constant MATIC = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

// AAVE
address constant AAVE_DATA_PROVIDER = 0x7551b5D2763519d4e37e8B81929D336De671d46d;
address constant AAVE_INCENTIVES = 0x357D51124f59836DeD84c8a1730D72B749d8BC23;

// QUICK
address constant QUICK = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
address constant DQUICK = 0xf28164A485B0B2C90639E47b0f377b4a438a16B1;

struct LpData {
    uint256 lpPrice;
    uint256 totalSupply;
    uint256 totalMarketUSD;
    uint112 reserves0;
    uint112 reserves1;
    address token0;
    address token1;
    string symbol0;
    string symbol1;
}

struct VeEthaInfo {
    address feeRecipient;
    uint256 minLockedAmount;
    uint256 penaltyRate;
    uint256 totalEthaLocked;
    uint256 totalVeEthaSupply;
    address multiFeeAddress;
    uint256 multiFeeTotalStaked;
    uint256 userVeEthaBalance;
    uint256 userEthaLocked;
    uint256 userLockEnds;
    uint256 multiFeeUserStake;
}

struct Rewards {
    address tokenAddress;
    uint256 rewardRate;
    uint periodFinish;
    uint balance;
    uint claimable;
}

struct SynthData {
    address stakingToken;
    address stakingContract;
    address rewardsToken;
    uint256 totalStaked;
    uint256 rewardsRate;
    uint256 periodFinish;
    uint256 rewardBalance;
}

struct ChefData {
    address stakingToken;
    address stakingContract;
    address rewardsToken;
    uint256 totalStaked;
    uint256 rewardsRate;
    uint256 periodFinish;
    uint256 rewardBalance;
}

struct VaultInfo {
    address depositToken;
    address rewardsToken;
    address strategy;
    address feeRecipient;
    address strategist;
    uint256 totalDeposits;
    uint256 performanceFee;
    uint256 withdrawalFee;
    uint256 lastDistribution;
}

struct QiVaultInfo {
    address stakingContract;
    address qiToken;
    address lpToken;
    address qiVault;
    uint poolId;
    uint debt;
    uint availableBorrow;
    uint collateral;
    uint safeLow;
    uint safeHigh;
    uint safeTarget;
}

struct AppStorage {
    mapping(address => address) aTokens;
    mapping(address => address) debtTokens;
    mapping(address => address) crTokens;
    mapping(address => address) priceFeeds;
    mapping(address => address) curvePools;
    address[] creamMarkets;
    address ethaRegistry;
    address feeManager;
}

library LibAppStorage {
    function diamondStorage() internal pure returns (AppStorage storage ds) {
        assembly {
            ds.slot := 0
        }
    }
}

contract Modifiers {
    AppStorage internal s;

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    function formatDecimals(address token, uint256 amount) internal view returns (uint256) {
        uint256 decimals = IERC20Metadata(token).decimals();

        if (decimals == 18) return amount;
        else return (amount * 1 ether) / (10 ** decimals);
    }
}
