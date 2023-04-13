// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/common/IUniswapV2ERC20.sol';
import '../../../../interfaces/common/IWETH.sol';
import '../../../../interfaces/common/IMasterChef.sol';
import '../../CompoundFeeManager.sol';
import '../../CompoundStrat.sol';

contract StrategyTraderJoeDualLP is CompoundStrat {
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

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        lpToken0 = IUniswapV2ERC20(want).token0();
        require(_nativeToLp0Route[0] == native, 'nativeToLp0Route[0] != native');
        require(_nativeToLp0Route[_nativeToLp0Route.length - 1] == lpToken0, 'nativeToLp0Route[last] != lpToken0');
        nativeToLp0Route = _nativeToLp0Route;

        lpToken1 = IUniswapV2ERC20(want).token1();
        require(_nativeToLp1Route[0] == native, 'nativeToLp1Route[0] != native');
        require(_nativeToLp1Route[_nativeToLp1Route.length - 1] == lpToken1, 'nativeToLp1Route[last] != lpToken1');
        nativeToLp1Route = _nativeToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(chef).deposit(poolId, wantBal);
            uint256 _toWrap = address(this).balance;
            IWETH(native).deposit{value: _toWrap}();
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external override {
        require(msg.sender == vault, '!vault');

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(chef).withdraw(poolId, _amount - wantBal);

            uint256 _toWrap = address(this).balance;

            if (_toWrap > 0) {
                IWETH(native).deposit{value: _toWrap}();
            }

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
        IMasterChef(chef).deposit(poolId, 0);
        uint256 _toWrap = address(this).balance;
        IWETH(native).deposit{value: _toWrap}();
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
        uint256 toNative = IERC20(output).balanceOf(address(this));

        if (toNative > 0)
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                toNative,
                0,
                outputToNativeRoute,
                address(this),
                block.timestamp
            );
        else return;

        uint256 nativeFeeBal = (IERC20(native).balanceOf(address(this)) * profitFee) / (MAX_FEE);

        _deductFees(native, callFeeRecipient, nativeFeeBal);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal override {
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)) / 2;

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
        (uint256 _amount, ) = IMasterChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function rewardsAvailable() public view returns (uint256 outputBal, uint256 nativeBal, address bonusToken) {
        (outputBal, bonusToken, , nativeBal) = IMasterChef(chef).pendingTokens(poolId, address(this));
    }

    function callReward() public view returns (uint256) {
        (uint256 outputBal, uint256 nativeBal, ) = rewardsAvailable();
        if (outputBal > 0) {
            try IUniswapV2Router(unirouter).getAmountsOut(outputBal, outputToNativeRoute) returns (
                uint256[] memory amountOut
            ) {
                nativeBal = nativeBal + amountOut[amountOut.length - 1];
            } catch {}
        }

        return (nativeBal * profitFee * callFee) / (MAX_FEE * MAX_FEE);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external override {
        require(msg.sender == vault, '!vault');

        IMasterChef(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public override onlyManager {
        pause();
        IMasterChef(chef).emergencyWithdraw(poolId);
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);
        IERC20(native).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return nativeToLp0Route;
    }

    function nativeToLp1() external view returns (address[] memory) {
        return nativeToLp1Route;
    }

    receive() external payable {}
}
