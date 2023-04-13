//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../../interfaces/IVotingEscrow.sol";
import "../../interfaces/IMultiFeeDistribution.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AvaModifiers, AVAX, IERC20} from "./AppStorage.sol";

contract AvaGettersFacet is AvaModifiers {
    function getRegistryAddress() external view returns (address) {
        return s.ethaRegistry;
    }

    function getPriceFeed(address _token) public view returns (address) {
        return s.priceFeeds[_token];
    }

    function getPrice(address token) external view returns (int256) {
        (, int256 price, , , ) = AggregatorV3Interface(s.priceFeeds[token]).latestRoundData();
        return price;
    }

    function getBalances(address[] calldata tokens, address user) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == AVAX) balances[i] = user.balance;
            else balances[i] = IERC20(tokens[i]).balanceOf(user);
        }

        return balances;
    }
}
