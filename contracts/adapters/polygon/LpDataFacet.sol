//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/common/IUniswapV2ERC20.sol';
import '../../interfaces/curve/ICurvePool.sol';
import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import {LpData, Modifiers, IERC20Metadata, IERC20} from './AppStorage.sol';

contract LpDataFacet is Modifiers {
    function getUniLpData(address lpPairToken) public view returns (LpData memory data) {
        uint256 market0;
        uint256 market1;

        //// Using Price Feeds
        int256 price0;
        int256 price1;

        //// Get Pair data
        IUniswapV2ERC20 pair = IUniswapV2ERC20(lpPairToken);
        (data.reserves0, data.reserves1, ) = pair.getReserves();
        data.token0 = pair.token0();
        data.token1 = pair.token1();
        data.symbol0 = IERC20Metadata(pair.token0()).symbol();
        data.symbol1 = IERC20Metadata(pair.token1()).symbol();
        data.totalSupply = pair.totalSupply();

        if (s.priceFeeds[data.token0] != address(0)) {
            (, price0, , , ) = AggregatorV3Interface(s.priceFeeds[data.token0]).latestRoundData();
            market0 = (formatDecimals(data.token0, uint256(data.reserves0)) * uint256(price0)) / (10 ** 8);
        }
        if (s.priceFeeds[data.token1] != address(0)) {
            (, price1, , , ) = AggregatorV3Interface(s.priceFeeds[data.token1]).latestRoundData();
            market1 = (formatDecimals(data.token1, uint256(data.reserves1)) * uint256(price1)) / (10 ** 8);
        }

        if (market0 == 0) {
            data.totalMarketUSD = 2 * market1;
        } else if (market1 == 0) {
            data.totalMarketUSD = 2 * market0;
        } else {
            data.totalMarketUSD = market0 + market1;
        }

        if (data.totalMarketUSD == 0) revert('MARKET ZERO');

        data.lpPrice = (data.totalMarketUSD * 1 ether) / data.totalSupply;
    }

    function getCurveLpInfo(address lpToken) public view returns (uint256 lpPrice, uint256 totalSupply) {
        if (s.curvePools[lpToken] != address(0)) {
            lpPrice = ICurvePool(s.curvePools[lpToken]).get_virtual_price();
            totalSupply = IERC20(lpToken).totalSupply();
        }
    }
}
