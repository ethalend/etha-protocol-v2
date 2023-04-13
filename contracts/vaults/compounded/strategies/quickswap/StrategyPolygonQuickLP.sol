// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/common/IUniswapV2ERC20.sol';
import '../../../../interfaces/quickswap/IStakingRewards.sol';
import '../../../../interfaces/quickswap/IDragonLair.sol';
import '../../CompoundStrat.sol';

contract StrategyPolygonQuickLP is CompoundStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public rewardPool;
    address public constant dragonsLair = address(0xf28164A485B0B2C90639E47b0f377b4a438a16B1);

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;

    constructor(
        address _want,
        address _rewardPool,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        want = _want;
        rewardPool = _rewardPool;

        require(_outputToNativeRoute.length >= 2);
        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        lpToken0 = IUniswapV2ERC20(want).token0();
        require(_outputToLp0Route[0] == output);
        require(_outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0);
        outputToLp0Route = _outputToLp0Route;

        lpToken1 = IUniswapV2ERC20(want).token1();
        require(_outputToLp1Route[0] == output);
        require(_outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1);
        outputToLp1Route = _outputToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IStakingRewards(rewardPool).stake(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external override whenNotPaused onlyVault {
        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IStakingRewards(rewardPool).withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal override whenNotPaused {
        IStakingRewards(rewardPool).getReward();
        uint256 lairBal = IERC20(dragonsLair).balanceOf(address(this));
        IDragonLair(dragonsLair).leave(lairBal);

        uint256 outputBal = IERC20(output).balanceOf(address(this));

        // If there are profits
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

        if (toNative > 0)
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                toNative,
                0,
                outputToNativeRoute,
                address(this),
                block.timestamp
            );
        else return;

        uint256 nativeFeeBal = IERC20(native).balanceOf(address(this));

        _deductFees(native, callFeeRecipient, nativeFeeBal);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal override {
        uint256 outputHalf = IERC20(output).balanceOf(address(this)) / 2;

        if (lpToken0 != output) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                outputHalf,
                0,
                outputToLp0Route,
                address(this),
                block.timestamp
            );
        }

        if (lpToken1 != output) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                outputHalf,
                0,
                outputToLp1Route,
                address(this),
                block.timestamp
            );
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapV2Router(unirouter).addLiquidity(
            lpToken0,
            lpToken1,
            lp0Bal,
            lp1Bal,
            1,
            1,
            address(this),
            block.timestamp
        );
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        return IStakingRewards(rewardPool).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        uint256 lairReward = IStakingRewards(rewardPool).earned(address(this));
        return IDragonLair(dragonsLair).dQUICKForQUICK(lairReward);
    }

    // returns native reward for calling harvest
    function callReward() public view returns (uint256) {
        if (callFee == 0) return 0;

        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            try IUniswapV2Router(unirouter).getAmountsOut(outputBal, outputToNativeRoute) returns (
                uint256[] memory amountOut
            ) {
                nativeOut = amountOut[amountOut.length - 1];
            } catch {}
        }

        return (nativeOut * profitFee * callFee) / (MAX_FEE * MAX_FEE);
    }

    // Returns the maximum amount of asset tokens that can be deposited
    function getMaximumDepositLimit() public pure returns (uint256) {
        return type(uint256).max;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external override onlyVault {
        // Claim rewards and compound
        _harvest(ethaFeeRecipient);

        // Withdraw all funds from gauge
        IStakingRewards(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).safeTransfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public override onlyManager {
        pause();
        IStakingRewards(rewardPool).withdraw(balanceOfPool());
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(rewardPool, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);

        if (output != lpToken0) IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);
        if (output != lpToken1) IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }
}
