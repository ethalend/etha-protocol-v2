//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/aave/IAaveIncentives.sol';
import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import {Modifiers, MATIC, WMATIC, AAVE_DATA_PROVIDER, AAVE_INCENTIVES, IERC20Metadata} from './AppStorage.sol';

interface IProtocolDataProvider {
    function getUserReserveData(address reserve, address user) external view returns (uint256 currentATokenBalance);

    function getReserveConfigurationData(
        address asset
    )
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
}

contract AaveFacet is Modifiers {
    function getAaveRewards(
        address[] memory _tokens
    ) public view returns (uint256[] memory _rewardsLending, uint256[] memory _rewardsBorrowing) {
        _rewardsLending = new uint256[](_tokens.length);
        _rewardsBorrowing = new uint256[](_tokens.length);

        (, int256 maticPrice, , , ) = AggregatorV3Interface(s.priceFeeds[MATIC]).latestRoundData();

        for (uint256 i = 0; i < _tokens.length; i++) {
            (, int256 tokenPrice, , , ) = AggregatorV3Interface(s.priceFeeds[_tokens[i]]).latestRoundData();

            // Lending Data
            {
                IERC20Metadata token_ = IERC20Metadata(s.aTokens[_tokens[i]]);
                uint256 totalSupply = formatDecimals(address(token_), token_.totalSupply());

                (uint256 emissionPerSecond, , ) = IAaveIncentives(AAVE_INCENTIVES).assets(address(token_));

                if (emissionPerSecond > 0) {
                    _rewardsLending[i] =
                        (emissionPerSecond * uint256(maticPrice) * 365 days * 1 ether) /
                        (totalSupply * uint256(tokenPrice));
                }
            }

            // Borrowing Data
            {
                IERC20Metadata token_ = IERC20Metadata(s.debtTokens[_tokens[i]]);
                uint256 totalSupply = formatDecimals(address(token_), token_.totalSupply());

                (uint256 emissionPerSecond, , ) = IAaveIncentives(AAVE_INCENTIVES).assets(address(token_));

                if (emissionPerSecond > 0) {
                    _rewardsBorrowing[i] =
                        (emissionPerSecond * uint256(maticPrice) * 365 days * 1 ether) /
                        (totalSupply * uint256(tokenPrice));
                }
            }
        }
    }

    function getAaveBalanceV2(address token, address account) public view returns (uint256) {
        (, , , , , , , , bool isActive, ) = IProtocolDataProvider(AAVE_DATA_PROVIDER).getReserveConfigurationData(
            token == MATIC ? WMATIC : token
        );

        if (!isActive) return 0;

        return IProtocolDataProvider(AAVE_DATA_PROVIDER).getUserReserveData(token == MATIC ? WMATIC : token, account);
    }

    function getLendingBalances(address[] calldata tokens, address user) external view returns (uint[] memory) {
        uint[] memory balances = new uint[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = getAaveBalanceV2(tokens[i], user);
        }

        return balances;
    }
}
