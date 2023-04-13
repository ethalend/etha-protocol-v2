//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../VolatStrat.sol';
import '../../../../interfaces/quickswap/IStakingRewards.sol';
import '../../../../interfaces/quickswap/IDragonLair.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract QuickStrat is VolatStrat {
    using SafeERC20 for IERC20;

    // ==== STATE ===== //

    IERC20 public constant QUICK = IERC20(0x831753DD7087CaC61aB5644b308642cc1c33Dc13);

    IDragonLair public constant DQUICK = IDragonLair(0xf28164A485B0B2C90639E47b0f377b4a438a16B1);

    // Quikswap LP Staking Rewards Contract
    IStakingRewards public staking;

    // ==== INITIALIZATION ===== //

    constructor(
        IVault vault_,
        IStakingRewards _staking,
        IERC20 _want,
        address _unirouter,
        address[] memory _outputToTargetRoute
    ) {
        output = IERC20(_outputToTargetRoute[0]);

        require(address(output) == address(QUICK));
        require(_outputToTargetRoute[_outputToTargetRoute.length - 1] == address(vault_.target()));

        vault = vault_;
        staking = _staking;
        want = _want;
        unirouter = _unirouter;
        outputToTargetRoute = _outputToTargetRoute;

        timelock = new Timelock(_msgSender(), 3 days);

        // Infite Approvals
        want.safeApprove(address(staking), type(uint256).max);
        want.safeApprove(address(vault), type(uint256).max);
        QUICK.safeApprove(address(vault), type(uint256).max);
    }

    // ==== GETTERS ===== //

    /**
		@dev total value of LP tokens staked on Quickswap Staking Contracts
	*/
    function calcTotalValue() public view override returns (uint256) {
        return staking.balanceOf(address(this));
    }

    /**
		@dev amount of claimable QUICK
	*/
    function totalYield() external view override returns (uint256) {
        uint256 _earned = staking.earned(address(this));

        return DQUICK.dQUICKForQUICK(_earned);
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

        staking.stake(balance);
    }

    /**
		@notice Redeem LP Tokens from Quickswap staking contract
		@dev can only be called by the vault contract
		@param amount amount of LP Tokens to withdraw
	*/
    function divest(uint256 amount) public override onlyVault {
        staking.withdraw(amount);

        want.safeTransfer(address(vault), amount);
    }

    /**
		@notice Claim QUICK rewards from staking contract
		@dev can only be called by the vault contract
		@dev only used when harvesting
	*/
    function claim() external override onlyVault returns (uint256 claimed) {
        staking.getReward();

        uint256 claimedDQUICK = DQUICK.balanceOf(address(this));
        DQUICK.leave(claimedDQUICK);

        claimed = QUICK.balanceOf(address(this));
        QUICK.safeTransfer(address(vault), claimed);
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
        require(outputToTargetRoute_[0] == address(QUICK));
        require(outputToTargetRoute_[outputToTargetRoute_.length - 1] == address(vault.target()));

        outputToTargetRoute = outputToTargetRoute_;
    }

    function setRouter(address router_) external override onlyTimelock {
        unirouter = router_;
    }
}
