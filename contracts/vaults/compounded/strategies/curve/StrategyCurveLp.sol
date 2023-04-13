// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/curve/IGaugeFactory.sol';
import '../../../../interfaces/curve/ICurveGauge.sol';
import '../../../../interfaces/curve/ICurveSwap.sol';
import '../../../../interfaces/common/IWETH.sol';
import '../../CompoundStrat.sol';

contract StrategyCurveLP is CompoundStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    address public depositToken;

    // Third party contracts
    address public gaugeFactory;
    address public rewardsGauge;
    address public pool;
    uint public poolSize;
    uint public depositIndex;
    bool public useUnderlying;
    bool public useMetapool;

    // Routes
    address[] public crvToNativeRoute;
    address[] public nativeToDepositRoute;

    struct Reward {
        address token;
        address[] toNativeRoute;
        uint minAmount; // minimum amount to be swapped to native
    }

    Reward[] public rewards;

    // if no CRV rewards yet, can enable later with custom router
    bool public crvEnabled = true;
    address public crvRouter;

    // if depositToken should be sent as unwrapped native
    bool public depositNative;

    constructor(
        address _want,
        address _gaugeFactory,
        address _gauge,
        address _pool,
        uint _poolSize,
        uint _depositIndex,
        bool _useUnderlying,
        bool _useMetapool,
        address[] memory _crvToNativeRoute,
        address[] memory _nativeToDepositRoute,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        want = _want;
        gaugeFactory = _gaugeFactory;
        rewardsGauge = _gauge;
        pool = _pool;
        poolSize = _poolSize;
        depositIndex = _depositIndex;
        useUnderlying = _useUnderlying;
        useMetapool = _useMetapool;

        output = _crvToNativeRoute[0];
        native = _crvToNativeRoute[_crvToNativeRoute.length - 1];
        crvToNativeRoute = _crvToNativeRoute;
        crvRouter = unirouter;

        require(_nativeToDepositRoute[0] == native, '_nativeToDepositRoute[0] != native');
        depositToken = _nativeToDepositRoute[_nativeToDepositRoute.length - 1];
        nativeToDepositRoute = _nativeToDepositRoute;

        if (gaugeFactory != address(0)) {
            harvestOnDeposit = true;
        }

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            ICurveGauge(rewardsGauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external override whenNotPaused onlyVault {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ICurveGauge(rewardsGauge).withdraw(_amount - wantBal);
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
        if (gaugeFactory != address(0)) {
            IGaugeFactory(gaugeFactory).mint(rewardsGauge);
        }
        ICurveGauge(rewardsGauge).claim_rewards(address(this));
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function swapRewardsToNative() internal {
        uint256 crvBal = IERC20(output).balanceOf(address(this));
        if (crvEnabled && crvBal > 0) {
            IUniswapV2Router(crvRouter).swapExactTokensForTokens(
                crvBal,
                0,
                crvToNativeRoute,
                address(this),
                block.timestamp
            );
        }
        // extras
        for (uint i; i < rewards.length; i++) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                IUniswapV2Router(unirouter).swapExactTokensForTokens(
                    bal,
                    0,
                    rewards[i].toNativeRoute,
                    address(this),
                    block.timestamp
                );
            }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal override {
        uint256 nativeFeeBal = (IERC20(native).balanceOf(address(this)) * profitFee) / MAX_FEE;
        _deductFees(native, callFeeRecipient, nativeFeeBal);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal override {
        uint256 depositBal;
        uint256 depositNativeAmount;
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (depositToken != native) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                nativeBal,
                0,
                nativeToDepositRoute,
                address(this),
                block.timestamp
            );
            depositBal = IERC20(depositToken).balanceOf(address(this));
        } else {
            depositBal = nativeBal;
            if (depositNative) {
                depositNativeAmount = nativeBal;
                IWETH(native).withdraw(depositNativeAmount);
            }
        }

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else ICurveSwap(pool).add_liquidity{value: depositNativeAmount}(amounts, 0);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else if (useMetapool) ICurveSwap(pool).add_liquidity(want, amounts, 0);
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

    function addRewardToken(address[] memory _rewardToNativeRoute, uint _minAmount) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, '!want');
        require(token != rewardsGauge, '!native');

        rewards.push(Reward(token, _rewardToNativeRoute, _minAmount));
        IERC20(token).safeApprove(unirouter, 0);
        IERC20(token).safeApprove(unirouter, type(uint).max);
    }

    function resetRewardTokens() external onlyManager {
        delete rewards;
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        return ICurveGauge(rewardsGauge).balanceOf(address(this));
    }

    function crvToNative() external view returns (address[] memory) {
        return crvToNativeRoute;
    }

    function nativeToDeposit() external view returns (address[] memory) {
        return nativeToDepositRoute;
    }

    function rewardToNative() external view returns (address[] memory) {
        return rewards[0].toNativeRoute;
    }

    function rewardToNative(uint i) external view returns (address[] memory) {
        return rewards[i].toNativeRoute;
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function setCrvEnabled(bool _enabled) external onlyManager {
        crvEnabled = _enabled;
    }

    function setCrvRoute(address _router, address[] memory _crvToNative) external onlyManager {
        require(_crvToNative[0] == output, '!crv');
        require(_crvToNative[_crvToNative.length - 1] == native, '!native');

        _removeAllowances();
        crvToNativeRoute = _crvToNative;
        crvRouter = _router;
        _giveAllowances();
    }

    function setDepositNative(bool _depositNative) external onlyOwner {
        depositNative = _depositNative;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return ICurveGauge(rewardsGauge).claimable_reward(address(this), output);
    }

    // returns rewards unharvested
    function rewardsAvailableByToken(address _rewardToken) public view returns (uint256) {
        return ICurveGauge(rewardsGauge).claimable_reward(address(this), _rewardToken);
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        if (callFee == 0) return 0;

        uint256 outputBal = rewardsAvailable();
        uint256[] memory amountOut = IUniswapV2Router(unirouter).getAmountsOut(outputBal, crvToNativeRoute);
        uint256 nativeOut = amountOut[amountOut.length - 1];

        return (nativeOut * profitFee * callFee) / (MAX_FEE * MAX_FEE);
    }

    // extra reward amount for calling harvest
    function callRewardByToken(uint i) public view returns (uint256) {
        if (callFee == 0) return 0;

        uint256 outputBal = rewardsAvailableByToken(rewards[i].token);
        uint256[] memory amountOut = IUniswapV2Router(unirouter).getAmountsOut(outputBal, rewards[i].toNativeRoute);
        uint256 rewardAmt = amountOut[amountOut.length - 1];

        return (rewardAmt * profitFee * callFee) / (MAX_FEE * MAX_FEE);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external override onlyVault {
        // Claim rewards and compound
        _harvest(ethaFeeRecipient);

        // Withdraw all funds from gauge
        ICurveGauge(rewardsGauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).safeTransfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public override onlyManager {
        pause();
        ICurveGauge(rewardsGauge).withdraw(balanceOfPool());
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(rewardsGauge, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(output).safeApprove(crvRouter, type(uint).max);
        IERC20(depositToken).safeApprove(pool, type(uint).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(rewardsGauge, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(output).safeApprove(crvRouter, 0);
        IERC20(depositToken).safeApprove(pool, 0);
    }

    receive() external payable {}
}
