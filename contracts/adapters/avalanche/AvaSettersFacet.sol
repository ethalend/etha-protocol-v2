//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {AvaModifiers} from "./AppStorage.sol";

contract AvaSettersFacet is AvaModifiers {
    function setRegistry(address _ethaRegistry) external onlyOwner {
        s.ethaRegistry = _ethaRegistry;
    }

    function setPriceFeeds(address[] memory _tokens, address[] memory _feeds) external onlyOwner {
        require(_tokens.length == _feeds.length, "!LENGTH");
        for (uint256 i = 0; i < _tokens.length; i++) {
            s.priceFeeds[_tokens[i]] = _feeds[i];
        }
    }

    function setCurvePool(address[] memory lpTokens, address[] memory pools) external onlyOwner {
        require(lpTokens.length == pools.length, "!LENGTH");
        for (uint256 i = 0; i < lpTokens.length; i++) {
            s.curvePools[lpTokens[i]] = pools[i];
        }
    }
}
