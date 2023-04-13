// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../../../interfaces/common/IUniswapV2Router.sol';
import '../../../../interfaces/common/IUniswapV2ERC20.sol';
import '../../../../interfaces/qiDao/IQiStakingRewards.sol';
import '../../../../interfaces/common/IDelegateRegistry.sol';
import '../../CompoundStrat.sol';
import '../../CompoundFeeManager.sol';

contract StrategyQiChefLP is CompoundStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    string public pendingRewardsFunctionName;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;

    address public qiDelegationContract;

    event VoterUpdated(address indexed voter);
    event DelegationContractUpdated(address indexed delegationContract);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route,
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
        require(_outputToLp0Route[0] == output, 'outputToLp0Route[0] != output');
        require(_outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0, 'outputToLp0Route[last] != lpToken0');
        outputToLp0Route = _outputToLp0Route;

        lpToken1 = IUniswapV2ERC20(want).token1();
        require(_outputToLp1Route[0] == output, 'outputToLp1Route[0] != output');
        require(_outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1, 'outputToLp1Route[last] != lpToken1');
        outputToLp1Route = _outputToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IQiStakingRewards(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external override {
        require(msg.sender == vault, '!vault');

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IQiStakingRewards(chef).withdraw(poolId, _amount - wantBal);
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
        IQiStakingRewards(chef).deposit(poolId, 0);
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
        (uint256 _amount, ) = IQiStakingRewards(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IQiStakingRewards(chef).pending(poolId, address(this));
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
        IQiStakingRewards(chef).withdraw(poolId, balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).safeTransfer(vault, wantBal);
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(chef, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    /// @notice Delegate Qi voting power to another address
    /// @param id   The delegate ID
    /// @param voter Address to delegate the votes to
    function _delegateVotingPower(bytes32 id, address voter) internal {
        IDelegateRegistry(qiDelegationContract).setDelegate(id, voter);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToLp0() external view returns (address[] memory) {
        return outputToLp0Route;
    }

    function outputToLp1() external view returns (address[] memory) {
        return outputToLp1Route;
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////      Admin functions      ///////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public override onlyManager {
        pause();
        IQiStakingRewards(chef).withdraw(poolId, balanceOfPool());
    }

    function setPendingRewardsFunctionName(string calldata _pendingRewardsFunctionName) external onlyManager {
        pendingRewardsFunctionName = _pendingRewardsFunctionName;
    }

    /// @notice Delegate Qi voting power to another address
    /// @param _id   The delegate ID
    /// @param _voter Address to delegate the votes to
    function delegateVotes(bytes32 _id, address _voter) external onlyManager {
        _delegateVotingPower(_id, _voter);
        emit VoterUpdated(_voter);
    }

    /// @notice Updates the delegation contract for Qi token Lock
    /// @param _delegationContract Updated delegation contract address
    function updateQiDelegationContract(address _delegationContract) external onlyManager {
        require(_delegationContract == address(0), 'ZERO_ADDRESS');
        qiDelegationContract = _delegationContract;
        emit DelegationContractUpdated(_delegationContract);
    }
}
