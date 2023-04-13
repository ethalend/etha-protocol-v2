// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/common/IUniswapV2ERC20.sol';
import '../../../../interfaces/sushi/IMiniChefV2.sol';
import '../../../../interfaces/sushi/ISushiRewarder.sol';
import '../../CompoundStrat.sol';

contract StrategySushiNativeDualLP is CompoundStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    // Routes
    address[] public outputToNativeRoute;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address[] memory _outputToNativeRoute,
        address[] memory _nativeToLp0Route,
        address[] memory _nativeToLp1Route,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        want = _want;
        poolId = _poolId;
        chef = _chef;

        require(_outputToNativeRoute.length >= 2);
        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        lpToken0 = IUniswapV2ERC20(want).token0();
        require(_nativeToLp0Route[0] == native);
        require(_nativeToLp0Route[_nativeToLp0Route.length - 1] == lpToken0);
        nativeToLp0Route = _nativeToLp0Route;

        lpToken1 = IUniswapV2ERC20(want).token1();
        require(_nativeToLp1Route[0] == native);
        require(_nativeToLp1Route[_nativeToLp1Route.length - 1] == lpToken1);
        nativeToLp1Route = _nativeToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMiniChefV2(chef).deposit(poolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external override whenNotPaused onlyVault {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMiniChefV2(chef).withdraw(poolId, _amount - wantBal, address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal override whenNotPaused {
        IMiniChefV2(chef).harvest(poolId, address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (outputBal > 0 || nativeBal > 0) {
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
        // swap all output to native
        uint256 toNative = IERC20(output).balanceOf(address(this));
        if (toNative > 0) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                toNative,
                0,
                outputToNativeRoute,
                address(this),
                block.timestamp
            );
        } else return;

        uint256 nativeFeeBal = (IERC20(native).balanceOf(address(this)) * profitFee) / MAX_FEE;

        _deductFees(native, callFeeRecipient, nativeFeeBal);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal override {
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)) / (2);

        if (lpToken0 != native) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                nativeHalf,
                0,
                nativeToLp0Route,
                address(this),
                block.timestamp
            );
        }

        if (lpToken1 != native) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                nativeHalf,
                0,
                nativeToLp1Route,
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
        (uint256 _amount, ) = IMiniChefV2(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external override onlyVault {
        // Claim rewards and compound
        _harvest(ethaFeeRecipient);

        // Withdraw all funds
        IMiniChefV2(chef).withdraw(poolId, balanceOfPool(), address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).safeTransfer(vault, wantBal);
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IMiniChefV2(chef).pendingSushi(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        if (callFee == 0) return 0;

        uint256 pendingReward;
        address rewarder = IMiniChefV2(chef).rewarder(poolId);
        if (rewarder != address(0)) {
            pendingReward = ISushiRewarder(rewarder).pendingToken(poolId, address(this));
        }

        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            try IUniswapV2Router(unirouter).getAmountsOut(outputBal, outputToNativeRoute) returns (
                uint256[] memory amountOut
            ) {
                nativeOut = amountOut[amountOut.length - 1];
            } catch {}
        }

        uint256 toNative = nativeOut + pendingReward;

        return (toNative * profitFee * callFee) / (MAX_FEE * MAX_FEE);
    }

    // Returns the maximum amount of asset tokens that can be deposited
    function getMaximumDepositLimit() public pure returns (uint256) {
        return type(uint256).max;
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public override onlyManager {
        pause();
        IMiniChefV2(chef).emergencyWithdraw(poolId, address(this));
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(native).safeApprove(unirouter, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);

        if (output != lpToken0 && native != lpToken0) IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);
        if (output != lpToken1 && native != lpToken1) IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(chef, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(output).safeApprove(unirouter, 0);

        if (output != lpToken0 && native != lpToken0) IERC20(lpToken0).safeApprove(unirouter, 0);
        if (output != lpToken1 && native != lpToken1) IERC20(lpToken1).safeApprove(unirouter, 0);
    }
}
