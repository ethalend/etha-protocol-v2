//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../../interfaces/IVotingEscrow.sol";
import "../../interfaces/IMultiFeeDistribution.sol";

import {VeEthaInfo, Rewards, Modifiers} from "./AppStorage.sol";

contract SettersFacet is Modifiers {
    function setFeeManager(address _feeManager) external onlyOwner {
        s.feeManager = _feeManager;
    }

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

    function setCreamTokens(address[] memory _tokens, address[] memory _crTokens) external onlyOwner {
        require(_tokens.length == _crTokens.length, "!LENGTH");
        for (uint256 i = 0; i < _tokens.length; i++) {
            s.crTokens[_tokens[i]] = _crTokens[i];
        }
    }
}
