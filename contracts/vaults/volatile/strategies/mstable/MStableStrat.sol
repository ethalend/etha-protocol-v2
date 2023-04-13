//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../VolatStrat.sol';
import {ISavingsContractV2, IBoostedDualVaultWithLockup} from '../../../../interfaces/mstable/IMStable.sol';
import '../../../../interfaces/common/IUniswapV2Router.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract MStableStrat is VolatStrat {
    using SafeERC20 for IERC20;

    // ==== STATE ===== //

    IERC20 public constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 public constant MTA = IERC20(0xF501dd45a1198C2E1b5aEF5314A68B9006D842E0);

    // mStable Save contract
    ISavingsContractV2 public savings = ISavingsContractV2(0x5290Ad3d83476CA6A2b178Cd9727eE1EF72432af);

    // mStable Boosted Vault
    IBoostedDualVaultWithLockup public boostedVault =
        IBoostedDualVaultWithLockup(0x32aBa856Dc5fFd5A56Bcd182b13380e5C855aa29);

    // ==== INITIALIZATION ===== //

    constructor(IVault _vault, IERC20 _want, address _unirouter, address[] memory _outputToTargetRoute) {
        vault = _vault;
        want = _want;
        unirouter = _unirouter;
        outputToTargetRoute = _outputToTargetRoute;

        timelock = new Timelock(msg.sender, 1 days);

        // Approve vault for withdrawals and claims
        want.safeApprove(address(vault), type(uint256).max);
        WMATIC.safeApprove(address(vault), type(uint256).max);
        MTA.safeApprove(address(vault), type(uint256).max);
        MTA.safeApprove(unirouter, type(uint256).max);

        // Approve for investing imUSD to vault
        IERC20(address(savings)).safeApprove(address(boostedVault), type(uint256).max);
    }

    // ==== GETTERS ===== //

    /**
		@dev total amount of imUSD tokens staked on mstable's vault
	*/
    function calcTotalValue() external view override returns (uint256) {
        return boostedVault.balanceOf(address(this));
    }

    function outputToTarget() external view override returns (address[] memory) {
        return outputToTargetRoute;
    }

    /**
		@dev amount of claimable MATIC
	*/
    function totalYield() external view override returns (uint256) {
        (uint256 mtaEarned, uint256 maticEarned) = boostedVault.earned(address(this));

        uint256 mtaToMatic;

        if (mtaEarned > 0) {
            address[] memory path = new address[](2);
            path[0] = address(MTA);
            path[1] = address(WMATIC);

            mtaToMatic = IUniswapV2Router(unirouter).getAmountsOut(mtaEarned, path)[path.length - 1];
        }

        return maticEarned + mtaToMatic;
    }

    // ==== MAIN FUNCTIONS ===== //

    /**
		@notice Invest LP Tokens into mStable staking contract
		@dev can only be called by the vault contract
		@dev credits = balance
	*/
    function invest() external override onlyVault {
        uint256 balance = want.balanceOf(address(this));
        require(balance > 0);

        boostedVault.stake(address(this), balance);
    }

    /**
		@notice Redeem LP Tokens from mStable staking contract
		@dev can only be called by the vault contract
		@param amount amount of LP Tokens to withdraw
	*/
    function divest(uint256 amount) public override onlyVault {
        boostedVault.withdraw(amount);

        uint256 received = savings.balanceOf(address(this));

        want.safeTransfer(address(vault), received);
    }

    /**
		@notice Redeem underlying assets from curve Aave pool and Matic rewards from gauge
		@dev can only be called by the vault contract
		@dev only used when harvesting
	*/
    function claim() external override onlyVault returns (uint256 claimed) {
        boostedVault.claimReward();

        uint256 claimedMTA = MTA.balanceOf(address(this));

        // If received MTA, swap to WMATIC
        if (claimedMTA > 0) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                claimedMTA,
                1,
                outputToTargetRoute,
                address(this),
                block.timestamp + 1
            )[outputToTargetRoute.length - 1];
        }

        claimed = WMATIC.balanceOf(address(this));
        WMATIC.safeTransfer(address(vault), claimed);
    }

    // ==== RESCUE ===== //

    // IMPORTANT: This function can only be called by the timelock to recover any token amount including deposited cTokens
    // However, the owner of the timelock must first submit their request and wait 7 days before confirming.
    // This gives depositors a good window to withdraw before a potentially malicious escape
    // The intent is for the owner to be able to rescue funds in the case they become stuck after launch
    // However, users should not trust the owner and watch the timelock contract least once a week on Etherscan
    // In the future, the timelock contract will be destroyed and the functionality will be removed after the code gets audited
    function rescue(address _token, address _to, uint256 _amount) external override onlyTimelock {
        require(msg.sender == address(timelock));
        IERC20(_token).transfer(_to, _amount);
    }

    function setSwapRoute(address[] memory outputToTargetRoute_) external override onlyTimelock {
        require(outputToTargetRoute_[0] == address(MTA));
        require(outputToTargetRoute_[outputToTargetRoute_.length - 1] == address(vault.target()));

        outputToTargetRoute = outputToTargetRoute_;
    }

    function setRouter(address router_) external override onlyTimelock {
        unirouter = router_;
    }
}
