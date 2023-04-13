//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../VolatStrat.sol';
import '../../../../interfaces/sushi/IMiniChefV2.sol';
import '../../../../interfaces/common/IUniswapV2Router.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract SushiStrat is VolatStrat {
    using SafeERC20 for IERC20;

    // ==== STATE ===== //
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant SUSHI_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    // Masterchef
    address public chef;
    uint public poolId;

    // ==== INITIALIZATION ===== //

    constructor(
        IVault _vault,
        IERC20 _want,
        address _chef,
        uint _poolId,
        address _unirouter,
        address[] memory outputToTargetRoute_
    ) {
        output = IERC20(outputToTargetRoute_[0]);
        chef = _chef;

        require(outputToTargetRoute_[0] == 0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a);
        require(outputToTargetRoute_[outputToTargetRoute_.length - 1] == address(_vault.target()));

        vault = _vault;
        want = _want;
        poolId = _poolId;
        unirouter = _unirouter;
        outputToTargetRoute = outputToTargetRoute_;

        timelock = new Timelock(_msgSender(), 3 days);

        // Infite Approvals
        want.safeApprove(chef, type(uint256).max);
        want.safeApprove(address(vault), type(uint256).max);
        IERC20(WMATIC).safeApprove(SUSHI_ROUTER, type(uint256).max);
    }

    // ==== GETTERS ===== //

    /**
		@dev total value of LP tokens staked on Quickswap Staking Contracts
	*/
    function calcTotalValue() external view override returns (uint256) {
        (uint256 _amount, ) = IMiniChefV2(chef).userInfo(poolId, address(this));
        return _amount;
    }

    /**
		@dev amount of claimable SUSHI
	*/
    function totalYield() external view override returns (uint256) {
        return IMiniChefV2(chef).pendingSushi(poolId, address(this));
    }

    function outputToTarget() external view override returns (address[] memory) {
        return outputToTargetRoute;
    }

    // ==== MAIN FUNCTIONS ===== //

    /**
		@notice Invest LP Tokens into Quickswap staking contract
		@dev can only be called by the vault contract
	*/
    function invest() external override onlyVault {
        uint256 balance = want.balanceOf(address(this));
        require(balance > 0);

        IMiniChefV2(chef).deposit(poolId, balance, address(this));
    }

    /**
		@notice Redeem LP Tokens from Quickswap staking contract
		@dev can only be called by the vault contract
		@param amount amount of LP Tokens to withdraw
	*/
    function divest(uint256 amount) public override onlyVault {
        IMiniChefV2(chef).withdraw(poolId, amount, address(this));

        want.safeTransfer(address(vault), amount);
    }

    /**
		@notice Claim QUICK rewards from staking contract
		@dev can only be called by the vault contract
		@dev only used when harvesting
	*/
    function claim() external override onlyVault returns (uint256 claimed) {
        IMiniChefV2(chef).harvest(poolId, address(this));

        // if wmatic received, swap for sushi
        uint256 wmaticBal = IERC20(WMATIC).balanceOf(address(this));
        if (wmaticBal > 0) {
            address[] memory path = new address[](2);
            path[0] = WMATIC;
            path[1] = address(output);
            IUniswapV2Router(SUSHI_ROUTER).swapExactTokensForTokens(wmaticBal, 0, path, address(this), block.timestamp);
        }

        uint256 sushiBal = output.balanceOf(address(this));
        output.safeTransfer(address(vault), sushiBal);

        return sushiBal;
    }

    // ==== RESCUE ===== //

    // IMPORTANT: This function can only be called by the timelock to recover any token amount including deposited cTokens
    // However, the owner of the timelock must first submit their request and wait timelock.delay() seconds before confirming.
    // This gives depositors a good window to withdraw before a potentially malicious escape
    // The intent is for the owner to be able to rescue funds in the case they become stuck after launch
    // However, users should not trust the owner and watch the timelock contract least once a week on Etherscan
    // In the future, the timelock contract will be destroyed and the functionality will be removed after the code gets audited
    function rescue(address _token, address _to, uint256 _amount) external override onlyTimelock {
        IERC20(_token).transfer(_to, _amount);
    }

    function setSwapRoute(address[] memory outputToTargetRoute_) external override onlyTimelock {
        require(outputToTargetRoute_[0] == address(output));
        require(outputToTargetRoute_[outputToTargetRoute_.length - 1] == address(vault.target()));

        outputToTargetRoute = outputToTargetRoute_;
    }

    function setRouter(address router_) external override onlyTimelock {
        unirouter = router_;
    }
}
