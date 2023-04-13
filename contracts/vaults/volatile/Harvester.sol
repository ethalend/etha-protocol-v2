//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/IVault.sol';
import '../../interfaces/common/IUniswapV2Router.sol';
import '../../interfaces/IVolatStrategy.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract Harvester is Ownable {
    using SafeERC20 for IERC20;

    event Harvested(address indexed vault, address indexed token, uint amount);

    uint256 public delay;

    constructor(uint256 _delay) {
        delay = _delay;
    }

    modifier onlyAfterDelay(IVault vault) {
        require(block.timestamp >= vault.lastDistribution() + delay, 'Not ready to harvest');
        _;
    }

    /**
		@notice Harvest vault using quickswap router
		@dev any user can harvest after delay has passed
	*/
    function harvestVault(IVault vault) public onlyAfterDelay(vault) {
        // Amount to Harvest
        uint256 afterFee = vault.harvest();
        require(afterFee > 0, '!Yield');

        IERC20 from = vault.rewards();
        IERC20 to = vault.target();
        address strat = vault.strat();
        address router = IVolatStrategy(strat).router();

        // Router path
        address[] memory path = IVolatStrategy(strat).outputToTarget();
        require(path[0] == address(from));
        require(path[path.length - 1] == address(to));

        // Swap underlying to target
        from.safeApprove(router, 0);
        from.safeApprove(router, afterFee);
        uint256 received = IUniswapV2Router(router).swapExactTokensForTokens(
            afterFee,
            1,
            path,
            address(this),
            block.timestamp + 1
        )[path.length - 1];

        // Send profits to vault
        to.approve(address(vault), received);
        vault.distribute(received);

        emit Harvested(address(vault), address(to), received);
    }

    /**
		@dev update delay required to harvest vault
	*/
    function setDelay(uint256 _delay) external onlyOwner {
        delay = _delay;
    }

    // no tokens should ever be stored on this contract. Any tokens that are sent here by mistake are recoverable by the owner
    function sweep(address _token) external onlyOwner {
        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
    }
}
