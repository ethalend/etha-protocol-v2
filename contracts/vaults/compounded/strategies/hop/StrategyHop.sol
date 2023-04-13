// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/hop/IStableRouter.sol';
import '../../../../interfaces/quickswap/IStakingRewards.sol';
import '../../CompoundStrat.sol';

contract StrategyHop is CompoundStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    address public depositToken;

    // Third party contracts
    address public rewardPool;
    address public stableRouter;
    uint256 public depositIndex;

    constructor(
        address _want,
        address _rewardPool,
        address _stableRouter,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        want = _want;
        rewardPool = _rewardPool;
        stableRouter = _stableRouter;
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IStakingRewards(rewardPool).stake(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external override {
        require(msg.sender == vault, '!vault');

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IStakingRewards(rewardPool).withdraw(_amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal override {
        IStakingRewards(rewardPool).getReward();
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal override {
        uint256 toNative = (IERC20(output).balanceOf(address(this)) * profitFee) / MAX_FEE;
        uint256 before = IERC20(native).balanceOf(address(this));

        if (toNative > 0) _swapToNative(toNative);
        else return;

        uint256 nativeFeeBal = IERC20(native).balanceOf(address(this)) - before;
        _deductFees(native, callFeeRecipient, nativeFeeBal);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal override {
        _swapToDeposit();

        uint256[] memory inputs = new uint256[](2);
        inputs[depositIndex] = IERC20(depositToken).balanceOf(address(this));
        IStableRouter(stableRouter).addLiquidity(inputs, 1, block.timestamp);
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        return IStakingRewards(rewardPool).balanceOf(address(this));
    }

    function rewardsAvailable() public view returns (uint256) {
        return IStakingRewards(rewardPool).earned(address(this));
    }

    // returns native reward for calling harvest
    function callReward() public view returns (uint256) {
        if (callFee == 0) return 0;

        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            nativeOut = _getAmountOut(outputBal);
        }

        return (nativeOut * profitFee * callFee) / (MAX_FEE * MAX_FEE);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external override {
        require(msg.sender == vault, '!vault');

        IStakingRewards(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public override onlyManager {
        pause();
        IStakingRewards(rewardPool).withdraw(balanceOfPool());
    }

    function _giveAllowances() internal virtual override {
        IERC20(want).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(depositToken).safeApprove(stableRouter, type(uint).max);
    }

    function _removeAllowances() internal virtual override {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(depositToken).safeApprove(stableRouter, 0);
    }

    function _swapToNative(uint256 outputAmt) internal virtual {}

    function _swapToDeposit() internal virtual {}

    function _getAmountOut(uint256 inputAmount) internal view virtual returns (uint256) {}

    function outputToNative() external view virtual returns (address[] memory) {}

    function outputToDeposit() external view virtual returns (address[] memory) {}
}
