// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/common/IUniswapV2ERC20.sol';
import '../../../../interfaces/common/IMasterChef.sol';
import '../../../../interfaces/curve/ICurveSwap.sol';
import '../../CompoundStrat.sol';
import '../../CompoundFeeManager.sol';

contract StrategyCurveChefLP is CompoundFeeManager, CompoundStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    address public depositToken;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public pool;
    uint public poolSize;
    uint public depositIndex;
    bool public useMetapool;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToDepositRoute;

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _pool,
        uint _poolSize,
        uint _depositIndex,
        bool _useMetapool,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToDepositRoute,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        want = _want;
        poolId = _poolId;
        chef = _chef;
        pool = _pool;
        poolSize = _poolSize;
        depositIndex = _depositIndex;
        useMetapool = _useMetapool;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        require(_outputToDepositRoute[0] == output, '_outputToDepositRoute[0] != output');
        depositToken = _outputToDepositRoute[_outputToDepositRoute.length - 1];
        outputToDepositRoute = _outputToDepositRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external override {
        require(msg.sender == vault, '!vault');

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(chef).withdraw(poolId, _amount - wantBal);
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
        IMasterChef(chef).deposit(poolId, 0);
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
        if (depositToken != output) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                outputBal,
                0,
                outputToDepositRoute,
                address(this),
                block.timestamp
            );
        }

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useMetapool) ICurveSwap(pool).add_liquidity(want, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useMetapool) ICurveSwap(pool).add_liquidity(want, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap(pool).add_liquidity(amounts, 0);
        }
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        (uint256 _amount, ) = IMasterChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IMasterChef(chef).pending(poolId, address(this));
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

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external override onlyVault {
        // Claim rewards and compound
        _harvest(ethaFeeRecipient);

        // Withdraw all funds from gauge
        IMasterChef(chef).withdraw(poolId, balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).safeTransfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public override onlyManager {
        pause();
        IMasterChef(chef).withdraw(poolId, balanceOfPool());
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(chef, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(depositToken).safeApprove(pool, type(uint).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(depositToken).safeApprove(pool, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToDeposit() external view returns (address[] memory) {
        return outputToDepositRoute;
    }
}
