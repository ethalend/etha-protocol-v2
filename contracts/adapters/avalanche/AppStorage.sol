// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {LibDiamond} from "../../libs/LibDiamond.sol";
import {LibMeta} from "../../libs/LibMeta.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

address constant AVAX = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

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
    address distribution;
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
    mapping(address => address) priceFeeds;
    mapping(address => address) curvePools;
    address ethaRegistry;
}

library LibAppStorage {
    function diamondStorage() internal pure returns (AppStorage storage ds) {
        assembly {
            ds.slot := 0
        }
    }
}

contract AvaModifiers {
    AppStorage internal s;

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    function formatDecimals(address token, uint256 amount) internal view returns (uint256) {
        uint256 decimals = IERC20Metadata(token).decimals();

        if (decimals == 18) return amount;
        else return (amount * 1 ether) / (10**decimals);
    }
}
