// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../../../../interfaces/hop/IStableRouter.sol';
import '../../../../libs/UniswapV3Utils.sol';
import './StrategyHop.sol';

contract StrategyHopSolidlyUniV3 is StrategyHop {
    using SafeERC20 for IERC20;

    // Routes
    bytes public outputToDepositPath;
    bytes public outputToNativePath;

    address public unirouterV3;

    constructor(
        address _want,
        address _rewardPool,
        address _stableRouter,
        address _unirouterV3,
        address[] memory _outputDepositRoute,
        address[] memory _outputToNativeRoute,
        uint24[] memory _outputToDepositFees,
        uint24[] memory _outputToNativeFees,
        CommonAddresses memory _commonAddresses
    ) StrategyHop(_want, _rewardPool, _stableRouter, _commonAddresses) {
        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];

        depositToken = _outputDepositRoute[_outputDepositRoute.length - 1];
        depositIndex = IStableRouter(stableRouter).getTokenIndex(depositToken);

        outputToDepositPath = UniswapV3Utils.routeToPath(_outputDepositRoute, _outputToDepositFees);
        outputToNativePath = UniswapV3Utils.routeToPath(_outputToNativeRoute, _outputToNativeFees);

        unirouterV3 = _unirouterV3;

        _giveAllowances();
    }

    function _swapToNative(uint256 outputAmt) internal virtual override {
        UniswapV3Utils.swap(unirouterV3, outputToNativePath, outputAmt);
    }

    function _swapToDeposit() internal virtual override {
        uint256 toDeposit = IERC20(output).balanceOf(address(this));
        UniswapV3Utils.swap(unirouterV3, outputToDepositPath, toDeposit);
    }

    function outputToNative() external view virtual override returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToNativePath);
    }

    function outputToDeposit() external view virtual override returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToDepositPath);
    }

    function _giveAllowances() internal virtual override {
        IERC20(want).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouterV3, type(uint).max);
        IERC20(depositToken).safeApprove(stableRouter, type(uint).max);
    }

    function _removeAllowances() internal virtual override {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouterV3, 0);
        IERC20(depositToken).safeApprove(stableRouter, 0);
    }
}
