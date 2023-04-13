// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/common/IUniswapV2ERC20.sol';
import '../../../../interfaces/common/IMasterChef.sol';
import '../../../../interfaces/stargate/IStargateRouter.sol';
import '../../../../interfaces/sushi/ITridentRouter.sol';
import '../../../../interfaces/sushi/IBentoBox.sol';
import '../../../../interfaces/sushi/IBentoPool.sol';
import '../../../../libs/StringUtils.sol';
import '../../CompoundStrat.sol';
import '../../CompoundFeeManager.sol';

contract StrategyStargateStaking is CompoundStrat {
    using SafeERC20 for IERC20;

    struct Routes {
        address[] outputToStableRoute;
        address outputToStablePool;
        address[] stableToNativeRoute;
        address[] stableToInputRoute;
    }

    // Tokens used
    address public stable;
    address public input;

    // Third party contracts
    address public chef = address(0x8731d54E9D02c286767d56ac03e8037C07e01e98);
    uint256 public poolId;
    address public stargateRouter = address(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd);
    address public quickRouter = address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    uint256 public routerPoolId;
    address public bentoBox = address(0x0319000133d3AdA02600f0875d2cf03D442C3367);

    // Extra functions
    string public pendingRewardsFunctionName;

    // Routes
    ITridentRouter.ExactInputSingleParams public outputToStableParams;
    address[] public outputToStableRoute;
    address[] public stableToNativeRoute;
    address[] public stableToInputRoute;

    constructor(
        address _want,
        uint256 _poolId,
        uint256 _routerPoolId,
        Routes memory _routes,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        want = _want;
        poolId = _poolId;
        routerPoolId = _routerPoolId;

        output = _routes.outputToStableRoute[0];
        stable = _routes.outputToStableRoute[_routes.outputToStableRoute.length - 1];
        native = _routes.stableToNativeRoute[_routes.stableToNativeRoute.length - 1];
        input = _routes.stableToInputRoute[_routes.stableToInputRoute.length - 1];

        require(_routes.stableToNativeRoute[0] == stable, 'stableToNativeRoute[0] != stable');
        require(_routes.stableToInputRoute[0] == stable, 'stableToInputRoute[0] != stable');
        outputToStableRoute = _routes.outputToStableRoute;
        stableToNativeRoute = _routes.stableToNativeRoute;
        stableToInputRoute = _routes.stableToInputRoute;

        outputToStableParams = ITridentRouter.ExactInputSingleParams(
            0,
            1,
            _routes.outputToStablePool,
            output,
            abi.encode(output, address(this), true)
        );

        IBentoBox(bentoBox).setMasterContractApproval(address(this), unirouter, true, 0, bytes32(0), bytes32(0));

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

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, '!vault');
            _harvest(tx.origin);
        }
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
        outputToStableParams.amountIn = IERC20(output).balanceOf(address(this));
        ITridentRouter(unirouter).exactInputSingleWithNativeToken(outputToStableParams);

        uint256 toNative = (IERC20(stable).balanceOf(address(this)) * profitFee) / MAX_FEE;

        if (toNative > 0) {
            IUniswapV2Router(quickRouter).swapExactTokensForTokens(
                toNative,
                0,
                stableToNativeRoute,
                address(this),
                block.timestamp
            );
        } else return;

        uint256 nativeFeeBal = IERC20(native).balanceOf(address(this));

        _deductFees(native, callFeeRecipient, nativeFeeBal);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal override {
        if (stable != input) {
            uint256 toInput = IERC20(stable).balanceOf(address(this));
            IUniswapV2Router(quickRouter).swapExactTokensForTokens(
                toInput,
                0,
                stableToInputRoute,
                address(this),
                block.timestamp
            );
        }

        uint256 inputBal = IERC20(input).balanceOf(address(this));
        IStargateRouter(stargateRouter).addLiquidity(routerPoolId, inputBal, address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        (uint256 _amount, ) = IMasterChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function setPendingRewardsFunctionName(string calldata _pendingRewardsFunctionName) external onlyManager {
        pendingRewardsFunctionName = _pendingRewardsFunctionName;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        string memory signature = StringUtils.concat(pendingRewardsFunctionName, '(uint256,address)');
        bytes memory result = Address.functionStaticCall(
            chef,
            abi.encodeWithSignature(signature, poolId, address(this))
        );
        return abi.decode(result, (uint256));
    }

    // native reward amount for calling harvest
    function callReward() external view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            bytes memory data = abi.encode(output, outputBal);
            uint256 inputBal = IBentoPool(outputToStableParams.pool).getAmountOut(data);
            if (inputBal > 0) {
                uint256[] memory amountOut = IUniswapV2Router(quickRouter).getAmountsOut(inputBal, stableToNativeRoute);
                nativeOut = amountOut[amountOut.length - 1];
            }
        }

        return (nativeOut * profitFee * callFee) / (MAX_FEE * MAX_FEE);
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
        IERC20(want).safeApprove(chef, type(uint).max);
        IERC20(output).safeApprove(bentoBox, type(uint).max);
        IERC20(stable).safeApprove(quickRouter, type(uint).max);
        IERC20(input).safeApprove(stargateRouter, type(uint).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(bentoBox, 0);
        IERC20(stable).safeApprove(quickRouter, 0);
        IERC20(input).safeApprove(stargateRouter, 0);
    }

    function outputToStable() external view returns (address[] memory) {
        return outputToStableRoute;
    }

    function stableToNative() external view returns (address[] memory) {
        return stableToNativeRoute;
    }

    function stableToInput() external view returns (address[] memory) {
        return stableToInputRoute;
    }
}
