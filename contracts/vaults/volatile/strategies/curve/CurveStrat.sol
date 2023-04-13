//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../VolatStrat.sol';
import '../../../../interfaces/curve/ICurveGauge.sol';
import '../../../../interfaces/curve/IGaugeFactory.sol';
import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../utils/Timelock.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract CurveStrat is VolatStrat {
    using SafeERC20 for IERC20;

    // ==== STATE ===== //

    ICurveGauge public gauge = ICurveGauge(0x20759F567BB3EcDB55c817c9a1d13076aB215EdC);

    IERC20 public constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 public constant CRV = IERC20(0x172370d5Cd63279eFa6d502DAB29171933a610AF);
    IGaugeFactory public constant GAUGE_FACTORY = IGaugeFactory(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    struct Reward {
        address token;
        address router;
        address[] toNativeRoute;
        uint minAmount; // minimum amount to be swapped to native
    }

    Reward[] public rewards;

    // ==== INITIALIZATION ===== //

    constructor(
        IVault _vault,
        Reward memory _reward,
        ICurveGauge _gauge,
        address _unirouter,
        address[] memory _outputToTargetRoute
    ) {
        output = IERC20(_outputToTargetRoute[0]);

        require(address(output) == address(WMATIC));
        require(_outputToTargetRoute[_outputToTargetRoute.length - 1] == address(_vault.target()));

        vault = _vault;
        gauge = _gauge;
        want = IERC20(gauge.lp_token());

        timelock = new Timelock(_msgSender(), 1 days);
        rewards.push(_reward);
        unirouter = _unirouter;
        outputToTargetRoute = _outputToTargetRoute;

        // Infite Approvals
        want.safeApprove(address(gauge), type(uint256).max);
        IERC20(_reward.token).safeApprove(_reward.router, type(uint256).max);
    }

    // ==== GETTERS ===== //

    /**
		@dev total value of LP tokens staked on Curve's Gauge
	*/
    function calcTotalValue() external view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    /**
		@dev amount of claimable CRV
	*/
    function totalYield() external view override returns (uint256) {
        return gauge.claimable_reward(address(this), address(CRV));
    }

    /**
		@dev amount of claimable for extra rewards
	*/
    function totalYieldByIndex(uint i) external view returns (uint256) {
        return gauge.claimable_reward(address(this), rewards[i].token);
    }

    /**
		@dev swap route for reward token
	*/
    function getRewardDetails(uint i) external view returns (address[] memory path, address routerAddress) {
        path = rewards[i].toNativeRoute;
        routerAddress = rewards[i].router;
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function outputToTarget() external view override returns (address[] memory) {
        return outputToTargetRoute;
    }

    // ==== MAIN FUNCTIONS ===== //

    /**
		@notice Invest LP Tokens into Curve's gauge
		@dev can only be called by the vault contract
	*/
    function invest() external override onlyVault {
        uint256 balance = want.balanceOf(address(this));
        require(balance > 0);

        gauge.deposit(balance);
    }

    /**
		@notice Redeem want assets from curve Aave pool
		@dev can only be called by the vault contract
		@dev wont always return the exact desired amount
		@param amount amount of want asset to withdraw
	*/
    function divest(uint256 amount) public override onlyVault {
        gauge.withdraw(amount);

        want.safeTransfer(address(vault), amount);
    }

    /**
		@notice Redeem underlying assets from curve Aave pool and Matic rewards from gauge
		@dev can only be called by the vault contract
		@dev only used when harvesting
	*/
    function claim() external override onlyVault returns (uint256 claimed) {
        GAUGE_FACTORY.mint(address(gauge));
        gauge.claim_rewards(address(this));

        for (uint i; i < rewards.length; i++) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                IUniswapV2Router(rewards[i].router).swapExactTokensForTokens(
                    bal,
                    0,
                    rewards[i].toNativeRoute,
                    address(this),
                    block.timestamp
                );
            }
        }

        claimed = WMATIC.balanceOf(address(this));
        if (claimed > 0) WMATIC.safeTransfer(address(vault), claimed);
    }

    // IMPORTANT: This function can only be called by the timelock to recover any token amount including deposited cTokens
    // However, the owner of the timelock must first submit their request and wait timelock.delay() seconds before confirming.
    // This gives depositors a good window to withdraw before a potentially malicious escape
    // The intent is for the owner to be able to rescue funds in the case they become stuck after launch
    // However, users should not trust the owner and watch the timelock contract least once a week on Etherscan
    // In the future, the timelock contract will be destroyed and the functionality will be removed after the code gets audited
    function rescue(address _token, address _to, uint256 _amount) external override onlyTimelock {
        IERC20(_token).transfer(_to, _amount);
    }

    /**
		@notice Add new reward token in curve gauge
		@dev can only be called by the vault owner
	*/
    function addRewardToken(address[] memory _rewardToNativeRoute, uint _minAmount, address _router) external {
        address owner = vault.owner();
        require(_msgSender() == owner, '!owner');

        address token = _rewardToNativeRoute[0];
        require(token != address(want), '!want');
        require(token != address(WMATIC), '!wmatic');

        rewards.push(Reward(token, _router, _rewardToNativeRoute, _minAmount));
        IERC20(token).safeApprove(address(_router), 0);
        IERC20(token).safeApprove(address(_router), type(uint).max);
    }

    /**
		@notice Reset reward tokens from curve gauge
		@dev can only be called by the vault owner
	*/
    function resetRewardTokens() external {
        address owner = vault.owner();
        require(_msgSender() == owner, '!owner');
        delete rewards;
    }

    function setSwapRoute(address[] memory outputToTargetRoute_) external override onlyTimelock {
        require(outputToTargetRoute_[0] == address(WMATIC));
        require(outputToTargetRoute_[outputToTargetRoute_.length - 1] == address(vault.target()));

        outputToTargetRoute = outputToTargetRoute_;
    }

    function setRouter(address unirouter_) external override onlyTimelock {
        unirouter = unirouter_;
    }
}
