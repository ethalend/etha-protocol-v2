//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Helpers.sol';
import '../interfaces/IMultiFeeDistribution.sol';

contract MultiFeeResolver is Helpers {
    event MultiFeeClaim(address indexed user, address[] tokens);

    /**
     * @dev claim rewards from the MultiFeeDistribution.
     * @param multiFeeContract address of the contract to claim the rewards.
     * @param user address of the user to claim the rewards.
     */
    function claim(address multiFeeContract, address user, address[] calldata rewardTokens) external {
        require(multiFeeContract != address(0), 'MultiFeeLogic: multifee contract cannot be address 0');
        require(user != address(0), 'MultiFeeLogic: user cannot be address 0');
        require(rewardTokens.length > 0, 'MultiFeeLogic: rewardTokens should be greater than 0');

        IMultiFeeDistribution(multiFeeContract).getReward(rewardTokens, user);

        emit MultiFeeClaim(_msgSender(), rewardTokens);
    }
}

contract MultiFeeLogic is MultiFeeResolver {
    string public constant name = 'MultiFeeLogic';
    uint8 public constant version = 1;

    receive() external payable {}
}
