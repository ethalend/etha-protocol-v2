// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import {LibError} from '../../../../libs/LibError.sol';
import '../../CompoundStrat.sol';

// Interfaces
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IUniswapV2Router} from '../../../../interfaces/common/IUniswapV2Router.sol';
import {IUniswapV2ERC20} from '../../../../interfaces/common/IUniswapV2ERC20.sol';
import {IQiStakingRewards} from '../../../../interfaces/qiDao/IQiStakingRewards.sol';
import {IERC20StablecoinQi} from '../../../../interfaces/qiDao/IERC20StablecoinQi.sol';
import {IDelegateRegistry} from '../../../../interfaces/common/IDelegateRegistry.sol';
import {IVGHST} from '../../../../interfaces/ghst/IVGHST.sol';

contract StrategyQiVaultVGHST is CompoundStrat {
    using SafeERC20 for IERC20;
    using SafeERC20 for IVGHST;

    // Address whitelisted to rebalance strategy
    address public rebalancer;

    // Tokens used
    IVGHST public assetToken; // vGHST
    IERC20 public mai = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1); // mai token
    IERC20 public qiToken = IERC20(0x580A84C73811E1839F75d86d75d88cCa0c241fF4); //qi token
    IERC20 public ghst = IERC20(0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7); //ghst token

    // QiDao addresses
    IERC20StablecoinQi public qiVault; // Qi Vault for Asset token
    address public qiStakingRewards; // 0xFFD2AA58Cca3A44120aaA42CEA2852348A9c2eA6 for Qi staking rewards masterchef contract
    uint256 public qiVaultId; // Vault ID

    // LP tokens and Swap paths
    address public lpToken0; //WMATIC
    address public lpToken1; //QI
    address public lpPairToken; //LP Pair token address

    address[] public assetToMai; // AssetToken to MAI
    address[] public maiToAsset; // Mai to AssetToken
    address[] public qiToAsset; // Rewards token to AssetToken
    address[] public maiToLp0; // MAI to WMATIC token
    address[] public maiToLp1; // MAI to QI token
    address[] public lp0ToMai; // LP0(WMATIC) to MAI
    address[] public lp1ToMai; // LP1(QI) to MAI

    // Config variables
    uint256 public lpFactor = 5;
    uint256 public qiRewardsPid = 1; // Staking rewards pool id for WMATIC-QI
    address public qiDelegationContract;

    // Chainlink Price Feed
    mapping(address => address) public priceFeeds;

    uint256 public SAFE_COLLAT_LOW = 180;
    uint256 public SAFE_COLLAT_TARGET = 200;
    uint256 public SAFE_COLLAT_HIGH = 220;

    // Events
    event VoterUpdated(address indexed voter);
    event DelegationContractUpdated(address indexed delegationContract);
    event SwapPathUpdated(address[] previousPath, address[] updatedPath);
    event StrategyRetired(address indexed stragegyAddress);
    event Harvested(address indexed harvester);
    event VaultRebalanced();
    event FarmUpdate(address newFarmContract, uint newPoolId);

    constructor(
        address _assetToken,
        address _qiVaultAddress,
        address _lpPairToken,
        address _qiStakingRewards,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        assetToken = IVGHST(_assetToken);
        lpPairToken = _lpPairToken;
        qiStakingRewards = _qiStakingRewards;

        // For Compound Strat
        want = _assetToken;
        output = address(qiToken);
        native = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); //WMATIC

        lpToken0 = IUniswapV2ERC20(lpPairToken).token0();
        lpToken1 = IUniswapV2ERC20(lpPairToken).token1();

        qiVault = IERC20StablecoinQi(_qiVaultAddress);
        qiVaultId = qiVault.createVault();
        if (!qiVault.exists(qiVaultId)) {
            revert LibError.QiVaultError();
        }
        _giveAllowances();
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////      Internal functions      //////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Provides token allowances to Unirouter, QiVault and Qi MasterChef contract
    function _giveAllowances() internal override {
        // Asset Token approvals
        assetToken.safeApprove(address(qiVault), 0);
        assetToken.safeApprove(address(qiVault), type(uint256).max);

        // GHST Token Approvals
        ghst.safeApprove(address(assetToken), 0);
        ghst.safeApprove(address(assetToken), type(uint256).max);

        ghst.safeApprove(unirouter, 0);
        ghst.safeApprove(unirouter, type(uint256).max);

        // Rewards token approval
        qiToken.safeApprove(unirouter, 0);
        qiToken.safeApprove(unirouter, type(uint256).max);

        // MAI token approvals
        mai.safeApprove(address(qiVault), 0);
        mai.safeApprove(address(qiVault), type(uint256).max);

        mai.safeApprove(unirouter, 0);
        mai.safeApprove(unirouter, type(uint256).max);

        // LP Token approvals
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);

        IERC20(lpPairToken).safeApprove(qiStakingRewards, 0);
        IERC20(lpPairToken).safeApprove(qiStakingRewards, type(uint256).max);

        IERC20(lpPairToken).safeApprove(unirouter, 0);
        IERC20(lpPairToken).safeApprove(unirouter, type(uint256).max);
    }

    /// @dev Revoke token allowances
    function _removeAllowances() internal override {
        // Asset Token approvals
        assetToken.safeApprove(address(qiVault), 0);

        // Rewards token approval
        qiToken.safeApprove(unirouter, 0);

        // GHST token approvals
        ghst.safeApprove(address(assetToken), 0);
        ghst.safeApprove(unirouter, 0);

        // MAI token approvals
        mai.safeApprove(address(qiVault), 0);
        mai.safeApprove(unirouter, 0);

        // LP Token approvals
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpPairToken).safeApprove(qiStakingRewards, 0);
        IERC20(lpPairToken).safeApprove(unirouter, 0);
    }

    function _swap(uint256 amount, address[] memory swapPath) internal {
        if (swapPath.length > 1) {
            IUniswapV2Router(unirouter).swapExactTokensForTokens(amount, 0, swapPath, address(this), block.timestamp);
        } else {
            revert LibError.InvalidSwapPath();
        }
    }

    function _getContractBalance(address token) internal view returns (uint256 tokenBalance) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Returns the total supply and market of LP
    /// @dev Will work only if price oracle for either one of the lp tokens is set
    /// @return lpTotalSupply Total supply of LP tokens
    /// @return totalMarketUSD Total market in USD of LP tokens
    function _getLPTotalMarketUSD() internal view returns (uint256 lpTotalSupply, uint256 totalMarketUSD) {
        uint256 market0;
        uint256 market1;

        //// Using Price Feeds
        int256 price0;
        int256 price1;

        IUniswapV2ERC20 pair = IUniswapV2ERC20(lpPairToken);
        lpTotalSupply = pair.totalSupply();
        (uint112 _reserve0, uint112 _reserve1, ) = pair.getReserves();

        if (priceFeeds[lpToken0] != address(0)) {
            (, price0, , , ) = AggregatorV3Interface(priceFeeds[lpToken0]).latestRoundData();
            market0 = (uint256(_reserve0) * uint256(price0)) / (10 ** 8);
        }
        if (priceFeeds[lpToken1] != address(0)) {
            (, price1, , , ) = AggregatorV3Interface(priceFeeds[lpToken1]).latestRoundData();
            market1 = (uint256(_reserve1) * uint256(price1)) / (10 ** 8);
        }

        if (market0 == 0) {
            totalMarketUSD = 2 * market1;
        } else if (market1 == 0) {
            totalMarketUSD = 2 * market0;
        } else {
            totalMarketUSD = market0 + market1;
        }
        if (totalMarketUSD == 0) revert LibError.PriceFeedError();
    }

    /// @notice Returns the LP amount equivalent of assetAmount
    /// @param assetAmount Amount of asset tokens for which equivalent LP tokens need to be calculated
    /// @return lpAmount USD equivalent of assetAmount in LP tokens
    function _getLPTokensFromAsset(uint256 assetAmount) internal view returns (uint256 lpAmount) {
        (uint256 lpTotalSupply, uint256 totalMarketUSD) = _getLPTotalMarketUSD();

        // Calculations
        // usdEquivalentOfEachLp = (totalMarketUSD / totalSupply);
        // usdEquivalentOfAsset = assetAmount * AssetTokenPrice;
        // lpAmount = usdEquivalentOfAsset / usdEquivalentOfEachLp
        lpAmount = (assetAmount * getAssetTokenPrice() * lpTotalSupply) / (totalMarketUSD * 10 ** 8);

        // Return additional amount(currently 110%) of the required LP tokens to account for slippage and future withdrawals
        lpAmount = (lpAmount * (100 + lpFactor)) / 100;

        // If calculated amount is greater than total deposited, withdraw everything
        uint256 totalLp = getStrategyLpDeposited();
        if (lpAmount > totalLp) {
            lpAmount = totalLp;
        }
    }

    /// @notice Returns the LP amount equivalent of maiAmount
    /// @param maiAmount Amount of asset tokens for which equivalent LP tokens need to be calculated
    /// @return lpAmount USD equivalent of maiAmount in LP tokens
    function _getLPTokensFromMai(uint256 maiAmount) internal view returns (uint256 lpAmount) {
        (uint256 lpTotalSupply, uint256 totalMarketUSD) = _getLPTotalMarketUSD();

        // Calculations
        // usdEquivalentOfEachLp = (totalMarketUSD / totalSupply);
        // usdEquivalentOfAsset = assetAmount * ethPriceSource;
        // lpAmount = usdEquivalentOfAsset / usdEquivalentOfEachLp
        lpAmount = (maiAmount * getMaiTokenPrice() * lpTotalSupply) / (totalMarketUSD * 10 ** 8);

        // Return additional amount(currently 110%) of the required LP tokens to account for slippage and future withdrawals
        lpAmount = (lpAmount * (100 + lpFactor)) / 100;

        // If calculated amount is greater than total deposited, withdraw everything
        uint256 totalLp = getStrategyLpDeposited();
        if (lpAmount > totalLp) {
            lpAmount = totalLp;
        }
    }

    /// @notice Deposits the asset token to QiVault from balance of this contract
    /// @notice Asset tokens must be transferred to the contract first before calling this function
    /// @param depositAmount AMount to be deposited to Qi Vault
    function _depositToQiVault(uint256 depositAmount) internal {
        // Deposit to QiDao vault
        qiVault.depositCollateral(qiVaultId, depositAmount);
    }

    /// @notice Borrows safe amount of MAI tokens from Qi Vault
    function _borrowTokens() internal {
        uint256 currentCollateralPercent = getCollateralPercent();
        if (currentCollateralPercent <= SAFE_COLLAT_TARGET && currentCollateralPercent != 0) {
            revert LibError.InvalidCDR(currentCollateralPercent, SAFE_COLLAT_TARGET);
        }

        uint256 amountToBorrow = safeAmountToBorrow();
        qiVault.borrowToken(qiVaultId, amountToBorrow);

        uint256 updatedCollateralPercent = getCollateralPercent();
        if (updatedCollateralPercent < SAFE_COLLAT_LOW && updatedCollateralPercent != 0) {
            revert LibError.InvalidCDR(updatedCollateralPercent, SAFE_COLLAT_LOW);
        }

        if (qiVault.checkLiquidation(qiVaultId)) revert LibError.LiquidationRisk();
    }

    /// @notice Repay MAI debt back to the qiVault
    function _repayMaiDebt() internal {
        uint256 maiDebt = getStrategyDebt();
        uint256 maiBalance = _getContractBalance(address(mai));

        if (maiDebt > maiBalance) {
            qiVault.payBackToken(qiVaultId, maiBalance);
        } else {
            qiVault.payBackToken(qiVaultId, maiDebt);
            _swap(_getContractBalance(address(mai)), maiToAsset);
            assetToken.enter(_getContractBalance(address(ghst)));
        }
    }

    /// @notice Swaps MAI for lpToken0 and lpToken 1 and adds liquidity to the AMM
    function addLiquidity() internal override {
        uint256 outputHalf = _getContractBalance(address(mai)) / 2;

        _swap(outputHalf, maiToLp0);
        _swap(outputHalf, maiToLp1);

        uint256 lp0Bal = _getContractBalance(lpToken0);
        uint256 lp1Bal = _getContractBalance(lpToken1);

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

        lp0Bal = _getContractBalance(lpToken0);
        lp1Bal = _getContractBalance(lpToken1);
    }

    /// @notice Deposits LP tokens to QiStaking Farm (MasterChef contract)
    /// @param amountToDeposit Amount of LP tokens to deposit to Farm
    function _depositLPToFarm(uint256 amountToDeposit) internal {
        IQiStakingRewards(qiStakingRewards).deposit(qiRewardsPid, amountToDeposit);
    }

    /// @notice Withdraw LP tokens from QiStaking Farm and removes liquidity from AMM
    /// @param withdrawAmount Amount of LP tokens to withdraw from Farm and AMM
    function _withdrawLpAndRemoveLiquidity(uint256 withdrawAmount) internal {
        IQiStakingRewards(qiStakingRewards).withdraw(qiRewardsPid, withdrawAmount);
        uint256 lpBalance = _getContractBalance(lpPairToken);
        IUniswapV2Router(unirouter).removeLiquidity(
            lpToken0,
            lpToken1,
            lpBalance,
            1,
            1,
            address(this),
            block.timestamp
        );
    }

    /// @notice Delegate Qi voting power to another address
    /// @param id   The delegate ID
    /// @param voter Address to delegate the votes to
    function _delegateVotingPower(bytes32 id, address voter) internal {
        IDelegateRegistry(qiDelegationContract).setDelegate(id, voter);
    }

    /// @notice Withdraws assetTokens from the Vault
    /// @param amountToWithdraw  Amount of assetTokens to withdraw from the vault
    function _withdrawFromVault(uint256 amountToWithdraw) internal {
        uint256 vaultCollateral = getStrategyCollateral();
        uint256 safeWithdrawAmount = safeAmountToWithdraw();

        if (amountToWithdraw == 0) revert LibError.InvalidAmount(0, 1);
        if (amountToWithdraw > vaultCollateral) revert LibError.InvalidAmount(amountToWithdraw, vaultCollateral);

        // Repay Debt from LP if required
        if (safeWithdrawAmount < amountToWithdraw) {
            // Debt is 50% of value of asset tokens when SAFE_COLLAT_TARGET = 200 (i.e 100/200 => 0.5)
            uint256 amountFromLP = ((amountToWithdraw - safeWithdrawAmount) * (100 + 10)) / SAFE_COLLAT_TARGET;

            //Withdraw from LP and repay debt
            uint256 lpAmount = _getLPTokensFromAsset(amountFromLP);
            _repayDebtLp(lpAmount);
        }

        // Calculate Max withdraw amount after repayment
        // console.log("Minimum collateral percent: ", qiVault._minimumCollateralPercentage());
        uint256 minimumCdr = qiVault._minimumCollateralPercentage() + 10;
        uint256 stratDebt = getStrategyDebt();
        uint256 maxWithdrawAmount = vaultCollateral - safeCollateralForDebt(stratDebt, minimumCdr);

        if (amountToWithdraw < maxWithdrawAmount) {
            // Withdraw collateral completely from qiVault
            qiVault.withdrawCollateral(qiVaultId, amountToWithdraw);
            assetToken.safeTransfer(msg.sender, amountToWithdraw);

            uint256 collateralPercent = getCollateralPercent();
            if (collateralPercent < SAFE_COLLAT_LOW) {
                // Rebalance from collateral
                rebalanceVault(false);
            }
            collateralPercent = getCollateralPercent();
            uint256 minCollateralPercent = qiVault._minimumCollateralPercentage();
            if (collateralPercent < minCollateralPercent && collateralPercent != 0) {
                revert LibError.InvalidCDR(collateralPercent, minCollateralPercent);
            }
        } else {
            revert LibError.InvalidAmount(safeWithdrawAmount, amountToWithdraw);
        }
    }

    /// @notice Charge Strategist and Performance fees
    /// @param callFeeRecipient Address to send the callFee (if set)
    function chargeFees(address callFeeRecipient) internal override {
        if (profitFee == 0) {
            return;
        }
        uint256 totalFee = (_getContractBalance(address(assetToken)) * profitFee) / MAX_FEE;

        _deductFees(address(assetToken), callFeeRecipient, totalFee);
    }

    /// @notice Harvest the rewards earned by Vault for more collateral tokens
    /// @param callFeeRecipient Address to send the callFee (if set)
    function _harvest(address callFeeRecipient) internal override {
        //1. Claim accrued Qi rewards from LP farm
        _depositLPToFarm(0);

        //2. Swap Qi tokens for asset tokens
        uint256 qiBalance = _getContractBalance(address(qiToken));

        if (qiBalance > 0) {
            _swap(qiBalance, qiToAsset);

            //3. Wrap to vGHST
            assetToken.enter(_getContractBalance(address(ghst)));

            //4. Charge performance fee
            chargeFees(callFeeRecipient);

            //5. deposit to Qi vault
            _depositToQiVault(_getContractBalance(address(assetToken)));

            lastHarvest = block.timestamp;
            emit Harvested(msg.sender);
        } else {
            revert LibError.HarvestNotReady();
        }
    }

    /// @notice Repay Debt by liquidating LP tokens
    /// @param lpAmount Amount of LP tokens to liquidate
    function _repayDebtLp(uint256 lpAmount) internal {
        //1. Withdraw LP tokens from Farm and remove liquidity
        _withdrawLpAndRemoveLiquidity(lpAmount);

        //2. Swap LP tokens for MAI tokens
        _swap(_getContractBalance(lpToken0), lp0ToMai);
        _swap(_getContractBalance(lpToken1), lp1ToMai);

        //3. Repay Debt to qiVault
        _repayMaiDebt();
    }

    /// @notice Repay Debt from deposited collateral tokens
    /// @param collateralAmount Amount of collateral tokens to withdraw
    function _repayDebtCollateral(uint256 collateralAmount) internal {
        //1. Withdraw assetToken from qiVault
        uint256 minimumCdr = qiVault._minimumCollateralPercentage();
        qiVault.withdrawCollateral(qiVaultId, collateralAmount);

        uint256 collateralPercent = getCollateralPercent();
        if (collateralPercent < minimumCdr && collateralPercent != 0) {
            revert LibError.InvalidCDR(collateralPercent, minimumCdr);
        }

        //2. Unwrap vGHST to GHST
        assetToken.leave(_getContractBalance(address(assetToken)));

        //3. Swap GHST for MAI
        _swap(_getContractBalance(address(ghst)), assetToMai);

        //4. Repay Debt to qiVault
        _repayMaiDebt();
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////      Admin functions      ///////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Delegate Qi voting power to another address
    /// @param _id   The delegate ID
    /// @param _voter Address to delegate the votes to
    function delegateVotes(bytes32 _id, address _voter) external onlyOwner {
        _delegateVotingPower(_id, _voter);
        emit VoterUpdated(_voter);
    }

    /// @notice Updates the delegation contract for Qi token Lock
    /// @param _delegationContract Updated delegation contract address
    function updateQiDelegationContract(address _delegationContract) external onlyOwner {
        if (_delegationContract == address(0)) revert LibError.InvalidAddress();
        qiDelegationContract = _delegationContract;
        emit DelegationContractUpdated(_delegationContract);
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateAssetToMai(address[] memory _swapPath) external onlyOwner {
        emit SwapPathUpdated(assetToMai, _swapPath);
        assetToMai = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateMaiToAsset(address[] memory _swapPath) external onlyOwner {
        emit SwapPathUpdated(maiToAsset, _swapPath);
        maiToAsset = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateQiToAsset(address[] memory _swapPath) external onlyOwner {
        emit SwapPathUpdated(qiToAsset, _swapPath);
        qiToAsset = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateMaiToLp0(address[] memory _swapPath) external onlyOwner {
        emit SwapPathUpdated(maiToLp0, _swapPath);
        maiToLp0 = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateMaiToLp1(address[] memory _swapPath) external onlyOwner {
        emit SwapPathUpdated(maiToLp1, _swapPath);
        maiToLp1 = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateLp0ToMai(address[] memory _swapPath) external onlyOwner {
        emit SwapPathUpdated(lp0ToMai, _swapPath);
        lp0ToMai = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateLp1ToMai(address[] memory _swapPath) external onlyOwner {
        emit SwapPathUpdated(lp1ToMai, _swapPath);
        lp1ToMai = _swapPath;
    }

    /// @notice Update LP factor for LP tokens calculation from assetToken
    /// @param _factor LP factor (in percent) of how much extra tokens to withdraw to account for slippage and future withdrawals
    function updateLpFactor(uint256 _factor) external onlyOwner {
        lpFactor = _factor;
    }

    /// @notice Update Safe collateral ratio percentage for SAFE_COLLAT_LOW
    /// @param _cdr Updated CDR Percent
    function updateSafeCollateralRatioLow(uint256 _cdr) external onlyOwner {
        SAFE_COLLAT_LOW = _cdr;
    }

    /// @notice Update Safe collateral ratio percentage for SAFE_COLLAT_TARGET
    /// @param _cdr Updated CDR Percent
    function updateSafeCollateralRatioTarget(uint256 _cdr) external onlyOwner {
        SAFE_COLLAT_TARGET = _cdr;
    }

    /// @notice Update Safe collateral ratio percentage for SAFE_COLLAT_HIGH
    /// @param _cdr Updated CDR Percent
    function updateSafeCollateralRatioHigh(uint256 _cdr) external onlyOwner {
        SAFE_COLLAT_HIGH = _cdr;
    }

    /// @notice Set Chainlink price feed for LP tokens
    /// @param _token Token for which price feed needs to be set
    /// @param _feed Address of Chainlink price feed
    function setPriceFeed(address _token, address _feed) external onlyOwner {
        priceFeeds[_token] = _feed;
    }

    /// @notice Repay Debt by liquidating LP tokens
    /// @param _lpAmount Amount of LP tokens to liquidate
    function repayDebtLp(uint256 _lpAmount) external onlyOwner {
        _repayDebtLp(_lpAmount);
    }

    /// @notice Repay Debt from deposited collateral tokens
    /// @param _collateralAmount Amount of collateral to repay
    function repayDebtCollateral(uint256 _collateralAmount) external onlyOwner {
        _repayDebtCollateral(_collateralAmount);
    }

    /// @notice Repay Debt by liquidating LP tokens
    function repayMaxDebtLp() external onlyOwner {
        uint256 lpbalance = getStrategyLpDeposited();
        _repayDebtLp(lpbalance);
    }

    /// @notice Repay Debt from deposited collateral tokens
    function repayMaxDebtCollateral() external onlyOwner {
        uint256 minimumCdr = qiVault._minimumCollateralPercentage() + 10;

        uint256 safeCollateralAmount = safeCollateralForDebt(getStrategyDebt(), minimumCdr);
        uint256 collateralToRepay = getStrategyCollateral() - safeCollateralAmount;
        _repayDebtCollateral(collateralToRepay);
    }

    /// @dev Rescues random funds stuck that the strat can't handle.
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        if (_token == address(assetToken)) revert LibError.InvalidToken();
        IERC20(_token).safeTransfer(msg.sender, _getContractBalance(_token));
    }

    function panic() public override onlyManager {
        pause();
        IQiStakingRewards(qiStakingRewards).withdraw(qiRewardsPid, balanceOfPool());
    }

    function setRebalancer(address _rebalancer) external onlyManager {
        rebalancer = _rebalancer;
    }

    /// @notice Update Qi Rewards contract and Pool ID for Qi MasterChef contract
    /// @param newQiStakingRewards new farm contract
    /// @param newQiRewardsPid Pool ID
    function updateQiFarm(address newQiStakingRewards, uint newQiRewardsPid) external onlyManager {
        // unstake from previous pool
        uint lpBalancePrev = getStrategyLpDeposited();
        IQiStakingRewards(qiStakingRewards).withdraw(qiRewardsPid, lpBalancePrev);
        IERC20(lpPairToken).safeApprove(qiStakingRewards, 0); // remove allowance from old pool

        // stake in new pool
        IERC20(lpPairToken).safeApprove(newQiStakingRewards, 0);
        IERC20(lpPairToken).safeApprove(newQiStakingRewards, type(uint256).max);
        IQiStakingRewards(newQiStakingRewards).deposit(newQiRewardsPid, lpBalancePrev);

        // update state variables
        qiStakingRewards = newQiStakingRewards;
        qiRewardsPid = newQiRewardsPid;

        emit FarmUpdate(newQiStakingRewards, newQiRewardsPid);
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////      External functions      /////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Returns the total supply and market of LP
    /// @dev Will work only if price oracle for either one of the lp tokens is set
    /// @return lpSupply Total supply of LP tokens
    /// @return totalMarketUSD Total market in USD of LP tokens
    function getLPTotalMarketUSD() public view returns (uint256 lpSupply, uint256 totalMarketUSD) {
        (lpSupply, totalMarketUSD) = _getLPTotalMarketUSD();
    }

    /// @notice Returns the assetToken Price from QiVault Contract Oracle
    /// @return assetTokenPrice Asset Token Price in USD
    function getAssetTokenPrice() public view returns (uint256 assetTokenPrice) {
        assetTokenPrice = qiVault.getEthPriceSource(); // Asset token price
        if (assetTokenPrice == 0) revert LibError.PriceFeedError();
    }

    /// @notice Returns the assetToken Price from QiVault Contract Oracle
    /// @return maiTokenPrice MAI Token Price in USD
    function getMaiTokenPrice() public view returns (uint256 maiTokenPrice) {
        maiTokenPrice = qiVault.getTokenPriceSource();
        if (maiTokenPrice == 0) revert LibError.PriceFeedError();
    }

    /// @notice Returns the Collateral Percentage of Strategy from QiVault
    /// @return cdr_percent Collateral Percentage
    function getCollateralPercent() public view returns (uint256 cdr_percent) {
        cdr_percent = qiVault.checkCollateralPercentage(qiVaultId);
    }

    /// @notice Returns the Debt of strategy from QiVault
    /// @return maiDebt MAI Debt of strategy
    function getStrategyDebt() public view returns (uint256 maiDebt) {
        maiDebt = qiVault.vaultDebt(qiVaultId);
    }

    /// @notice Returns the total collateral of strategy from QiVault
    /// @return collateral Collateral deposited by strategy into QiVault
    function getStrategyCollateral() public view returns (uint256 collateral) {
        collateral = qiVault.vaultCollateral(qiVaultId);
    }

    /// @notice Returns the total LP deposited balance of strategy from Qifarm
    /// @return lpBalance LP deposited by strategy into Qifarm
    function getStrategyLpDeposited() public view returns (uint256 lpBalance) {
        lpBalance = IQiStakingRewards(qiStakingRewards).deposited(qiRewardsPid, address(this));
    }

    /// @notice Returns the maximum amount of asset tokens that can be deposited
    /// @return depositLimit Maximum amount of asset tokens that can be deposited to strategy
    function getMaximumDepositLimit() public view returns (uint256 depositLimit) {
        uint256 maiAvailable = qiVault.getDebtCeiling();
        depositLimit = (maiAvailable * SAFE_COLLAT_TARGET * 10 ** 8) / (getAssetTokenPrice() * 100);
    }

    /// @notice Returns the safe amount to borrow from qiVault considering Debt and Collateral
    /// @return amountToBorrow Safe amount of MAI to borrow from vault
    function safeAmountToBorrow() public view returns (uint256 amountToBorrow) {
        uint256 safeDebt = safeDebtForCollateral(getStrategyCollateral(), SAFE_COLLAT_TARGET);
        uint256 currentDebt = getStrategyDebt();
        if (safeDebt > currentDebt) {
            amountToBorrow = safeDebt - currentDebt;
        } else {
            amountToBorrow = 0;
        }
    }

    /// @notice Returns the safe amount to withdraw from qiVault considering Debt and Collateral
    /// @return amountToWithdraw Safe amount of assetTokens to withdraw from vault
    function safeAmountToWithdraw() public view returns (uint256 amountToWithdraw) {
        uint256 safeCollateral = safeCollateralForDebt(getStrategyDebt(), (SAFE_COLLAT_LOW + 1));
        uint256 currentCollateral = getStrategyCollateral();
        if (currentCollateral > safeCollateral) {
            amountToWithdraw = currentCollateral - safeCollateral;
        } else {
            amountToWithdraw = 0;
        }
    }

    /// @notice Returns the safe Debt for collateral(passed as argument) from qiVault
    /// @param collateral Amount of collateral tokens for which safe Debt is to be calculated
    /// @return safeDebt Safe amount of MAI than can be borrowed from qiVault
    function safeDebtForCollateral(
        uint256 collateral,
        uint256 collateralPercent
    ) public view returns (uint256 safeDebt) {
        uint256 safeDebtValue = (collateral * getAssetTokenPrice() * 100) / collateralPercent;
        safeDebt = safeDebtValue / getMaiTokenPrice();
    }

    /// @notice Returns the safe collateral for debt(passed as argument) from qiVault
    /// @param debt Amount of MAI tokens for which safe collateral is to be calculated
    /// @return safeCollateral Safe amount of collateral tokens for qiVault
    function safeCollateralForDebt(
        uint256 debt,
        uint256 collateralPercent
    ) public view returns (uint256 safeCollateral) {
        uint256 collateralValue = (collateralPercent * debt * getMaiTokenPrice()) / 100;
        safeCollateral = collateralValue / getAssetTokenPrice();
    }

    /// @notice Deposits the asset token to QiVault from balance of this contract
    /// @dev Asset tokens must be transferred to the contract first before calling this function
    function deposit() public override whenNotPaused onlyVault {
        _depositToQiVault(_getContractBalance(address(assetToken)));

        //Check CDR ratio, if below 220% don't borrow, else borrow
        uint256 cdr_percent = getCollateralPercent();

        if (cdr_percent > SAFE_COLLAT_HIGH) {
            _borrowTokens();
            addLiquidity();
            _depositLPToFarm(_getContractBalance(lpPairToken));
        } else if (cdr_percent == 0 && getStrategyCollateral() != 0) {
            // Note: Special case for initial deposit(as CDR is returned 0 when Debt is 0)
            // Borrow minDebt (or 1 wei if 0) to initialize
            uint _debt = qiVault.minDebt() > 0 ? qiVault.minDebt() : 1;
            qiVault.borrowToken(qiVaultId, _debt);
        }
    }

    /// @notice Withdraw deposited tokens from the Vault
    function withdraw(uint256 withdrawAmount) public override whenNotPaused onlyVault {
        _withdrawFromVault(withdrawAmount);
    }

    /// @notice Rebalances the vault to a safe Collateral to Debt ratio
    /// @dev If Collateral to Debt ratio is below SAFE_COLLAT_LOW,
    /// then -> Withdraw lpAmount from Farm > Remove liquidity from LP > swap Qi for WMATIC > Deposit WMATIC to vault
    // If CDR is greater than SAFE_COLLAT_HIGH,
    /// then -> Borrow more MAI > Swap for Qi and WMATIC > Deposit to Quickswap LP > Deposit to Qi Farm
    function rebalanceVault(bool repayFromLp) public whenNotPaused {
        if (rebalancer != address(0)) require(msg.sender == rebalancer, '!whitelisted');

        uint256 cdr_percent = getCollateralPercent();

        if (cdr_percent < SAFE_COLLAT_TARGET) {
            // Get amount of LP tokens to sell for asset tokens
            uint256 safeDebt = safeDebtForCollateral(getStrategyCollateral(), SAFE_COLLAT_TARGET);
            uint256 debtToRepay = getStrategyDebt() - safeDebt;

            if (repayFromLp) {
                uint256 lpAmount = _getLPTokensFromMai(debtToRepay);
                _repayDebtLp(lpAmount);
            } else {
                // Repay from collateral
                uint256 requiredCollateralValue = ((SAFE_COLLAT_TARGET + 10) * debtToRepay * getMaiTokenPrice()) / 100;
                uint256 collateralToRepay = requiredCollateralValue / getAssetTokenPrice();

                uint256 stratCollateral = getStrategyCollateral();
                uint256 minimumCdr = qiVault._minimumCollateralPercentage() + 5;
                uint256 stratDebt = getStrategyDebt();
                uint256 minCollateralForDebt = safeCollateralForDebt(stratDebt, minimumCdr);
                uint256 maxWithdrawAmount;
                if (stratCollateral > minCollateralForDebt) {
                    maxWithdrawAmount = stratCollateral - minCollateralForDebt;
                } else {
                    revert LibError.InvalidAmount(1, 1);
                }
                if (collateralToRepay > maxWithdrawAmount) {
                    collateralToRepay = maxWithdrawAmount;
                }
                _repayDebtCollateral(collateralToRepay);
            }
            //4. Check updated CDR and verify
            uint256 updated_cdr = getCollateralPercent();
            if (updated_cdr < SAFE_COLLAT_TARGET && updated_cdr != 0)
                revert LibError.InvalidCDR(updated_cdr, SAFE_COLLAT_TARGET);
        } else if (cdr_percent > SAFE_COLLAT_HIGH) {
            //1. Borrow tokens
            _borrowTokens();

            //2. Swap and add liquidity
            addLiquidity();

            //3. Deposit LP to farm
            _depositLPToFarm(_getContractBalance(lpPairToken));
        } else {
            revert LibError.InvalidCDR(0, 0);
        }
        emit VaultRebalanced();
    }

    /// @notice Repay MAI debt back to the qiVault
    /// @dev The sender must have sufficient allowance and balance
    function repayDebt(uint256 amount) public {
        mai.safeTransferFrom(msg.sender, address(this), amount);
        _repayMaiDebt();
    }

    function balanceOfPool() public view override returns (uint256 poolBalance) {
        uint256 assetBalance = getStrategyCollateral();

        // For Debt, also factor in 0.5% repayment fee
        // This fee is charged by QiDao only on the Debt (amount of MAI borrowed)
        uint256 maiDebt = (getStrategyDebt() * (10000 + 50)) / 10000;
        uint256 lpBalance = getStrategyLpDeposited();

        IUniswapV2ERC20 pair = IUniswapV2ERC20(lpPairToken);
        uint256 lpTotalSupply = pair.totalSupply();
        (uint112 _reserve0, uint112 _reserve1, ) = pair.getReserves();

        uint256 balance0 = (lpBalance * _reserve0) / lpTotalSupply;
        uint256 balance1 = (lpBalance * _reserve1) / lpTotalSupply;

        uint256 maiBal0;
        if (balance0 > 0) {
            try IUniswapV2Router(unirouter).getAmountsOut(balance0, lp0ToMai) returns (uint256[] memory amountOut0) {
                maiBal0 = amountOut0[amountOut0.length - 1];
            } catch {}
        }

        uint256 maiBal1;
        if (balance1 > 0) {
            try IUniswapV2Router(unirouter).getAmountsOut(balance1, lp1ToMai) returns (uint256[] memory amountOut1) {
                maiBal1 = amountOut1[amountOut1.length - 1];
            } catch {}
        }
        uint256 totalMaiReceived = maiBal0 + maiBal1;

        if (maiDebt > totalMaiReceived) {
            uint256 diffAsset = ((maiDebt - totalMaiReceived) * 10 ** 8) / getAssetTokenPrice();
            poolBalance = assetBalance - diffAsset;
        } else {
            uint256 diffAsset = ((totalMaiReceived - maiDebt) * 10 ** 8) / getAssetTokenPrice();
            poolBalance = assetBalance + diffAsset;
        }
    }

    function balanceOfWant() public view override returns (uint256 poolBalance) {
        return _getContractBalance(address(assetToken));
    }

    /// @notice called as part of strat migration. Sends all the available funds back to the vault.
    /// NOTE: All QiVault debt must be paid before this function is called
    function retireStrat() external override onlyVault {
        require(getStrategyDebt() == 0, 'Debt');

        // Withdraw asset token balance from vault and strategy
        qiVault.withdrawCollateral(qiVaultId, getStrategyCollateral());
        assetToken.safeTransfer(vault, _getContractBalance(address(assetToken)));

        // Withdraw LP balance from staking rewards
        uint256 lpBalance = getStrategyLpDeposited();
        if (lpBalance > 0) {
            IQiStakingRewards(qiStakingRewards).withdraw(qiRewardsPid, lpBalance);
            IERC20(lpPairToken).safeTransfer(vault, lpBalance);
        }
        emit StrategyRetired(address(this));
    }
}
