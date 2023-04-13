// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import {LibError} from '../../../../libs/LibError.sol';
import {UniV3Swap} from '../../../../libs/UniV3Swap.sol';
import {Path} from '../../../../libs/Path.sol';
import '../../CompoundStrat.sol';

// Interfaces
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IPool} from '../../../../interfaces/aave/IAavePool.sol';
import {IFlashLoanReceiver} from '../../../../interfaces/aave/IFlashLoanReceiver.sol';
import {IAaveProtocolDataProvider} from '../../../../interfaces/aave/IAaveProtocolDataProvider.sol';
import {ICurvePoolMatic} from '../../../../interfaces/curve/ICurvePoolMatic.sol';
import {IWETH} from '../../../../interfaces/common/IWETH.sol';
import {IAaveRewardsController as IAaveIncentives} from '../../../../interfaces/aave/IAaveRewardsController.sol';

import 'hardhat/console.sol';

interface Adapter {
    function getPrice(address token) external view returns (int256);
}

contract StrategyAaveLeverageMaticMock is CompoundStrat, IFlashLoanReceiver {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;
    using Path for bytes;

    enum ACTION {
        DEPOSIT,
        WITHDRAW,
        REPAY,
        PANIC
    }

    struct Reward {
        address token;
        address aaveToken;
        bytes toNativeRoute;
        uint minAmount; // minimum amount to be swapped to native
    }

    Reward[] public rewards;

    // Address whitelisted to rebalance strategy
    address public rebalancer;

    // Tokens used
    IERC20 public assetToken; // deposited token to strat
    IERC20 public stMatic = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4); // stMatic token

    // Aave addresses
    address aPolSTMATIC = 0xEA1132120ddcDDA2F119e99Fa7A27a0d036F7Ac9;
    address vPolWMATIC = 0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8;
    IPool aavePool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    IAaveProtocolDataProvider dataProvider = IAaveProtocolDataProvider(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654);
    IAaveIncentives aaveIncentives = IAaveIncentives(0x929EC64c34a17401F460460D4B9390518E5B473e);

    // Curve addresses
    ICurvePoolMatic public stMaticPool = ICurvePoolMatic(0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28);

    uint256 public SAFE_LTV_LOW = 6000;
    uint256 public SAFE_LTV_TARGET = 7000;
    uint256 public SAFE_LTV_HIGH = 8000;
    uint public securityFactor = 15;

    uint16 public referralCode = 0;

    // Events
    event VoterUpdated(address indexed voter);
    event DelegationContractUpdated(address indexed delegationContract);
    event SwapPathUpdated(address[] previousPath, address[] updatedPath);
    event StrategyRetired(address indexed stragegyAddress);
    event Harvested(address indexed harvester);
    event VaultRebalanced();

    constructor(address _assetToken, CommonAddresses memory _commonAddresses) CompoundStratManager(_commonAddresses) {
        assetToken = IERC20(_assetToken);

        // For Compound Strat
        want = _assetToken;
        native = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); //WMATIC
        output = native;

        _giveAllowances();

        aavePool.setUserEMode(2); // MATIC correlated, bump max ltv to 92.5%
    }

    /// @dev Temporal function to deposit collateral and reduce LTV
    /// TODO: REMOVE FOR DEPLOYMENT!!!
    function managerDeposit(uint amtDeposit) public onlyManager {
        // Swap to stMatic and Deposit as collateral in Aave
        IERC20(native).safeTransferFrom(_msgSender(), address(this), amtDeposit);
        uint received = _swapCurve(native, amtDeposit);
        _depositToAavePool(received);
    }

    /// @dev Temporal function to withdraw collateral and increase LTV
    /// TODO: REMOVE FOR DEPLOYMENT!!!
    function managerWithdraw(uint withdrawAmount) public onlyManager {
        uint amtCollatToWithdraw = _getValueInStMatic((withdrawAmount * (10000 + securityFactor)) / 10000); // account for swap fees
        _withdrawFromAavePool(amtCollatToWithdraw);
        stMatic.safeTransfer(_msgSender(), _getContractBalance(address(stMatic)));
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////      Internal functions      //////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Provides token allowances to Unirouter, QiVault and Qi MasterChef contract
    function _giveAllowances() internal override {
        // For swapping in curve
        assetToken.safeApprove(address(stMaticPool), 0);
        assetToken.safeApprove(address(stMaticPool), type(uint256).max);

        stMatic.safeApprove(address(stMaticPool), 0);
        stMatic.safeApprove(address(stMaticPool), type(uint256).max);

        // For repaying debt in aave
        assetToken.safeApprove(address(aavePool), 0);
        assetToken.safeApprove(address(aavePool), type(uint256).max);

        // For depositing collat into aave
        stMatic.safeApprove(address(aavePool), 0);
        stMatic.safeApprove(address(aavePool), type(uint256).max);
    }

    /// @dev Revoke token allowances
    function _removeAllowances() internal override {
        // Asset Token approvals
        assetToken.safeApprove(address(stMaticPool), 0);
        stMatic.safeApprove(address(stMaticPool), 0);
        stMatic.safeApprove(address(aavePool), 0);
    }

    /// @dev Internal function to swap stMATIC and WMATIC in curve
    /// TODO: check with other DEXs
    function _swapCurve(address src, uint amountIn) internal returns (uint received) {
        if (amountIn == 0) return 0;

        if (stMaticPool.coins(0) == src) {
            received = stMaticPool.exchange(0, 1, amountIn, 0, false);
        } else if (stMaticPool.coins(1) == src) {
            received = stMaticPool.exchange(1, 0, amountIn, 0, false);
        } else {
            revert LibError.InvalidAddress();
        }
    }

    function _getContractBalance(address token) internal view returns (uint256 tokenBalance) {
        return IERC20(token).balanceOf(address(this));
    }

    function _getValueInMatic(uint stMaticAmt) internal view returns (uint) {
        if (stMaticAmt == 0) return 0;
        return stMaticPool.get_dy(0, 1, stMaticAmt);
    }

    function _getValueInStMatic(uint maticAmt) internal view returns (uint) {
        if (maticAmt == 0) return 0;
        return stMaticPool.get_dy(1, 0, maticAmt);
    }

    /// @notice Withdraws assetTokens from the Pool
    /// @param amountToWithdraw  Amount of assetTokens to withdraw from the pool
    function _withdrawFromPool(uint256 amountToWithdraw) internal {
        uint256 collateral = getStrategyCollateral(); // in WMATIC value
        console.log('collateral', collateral);
        uint256 safeWithdrawAmount = safeAmountToWithdraw(SAFE_LTV_TARGET); // in WMATIC value

        console.log('amountToWithdraw', amountToWithdraw);
        console.log('safeWithdrawAmount', safeWithdrawAmount);
        console.log('wmatic Balance before', _getContractBalance(native));

        if (amountToWithdraw == 0) revert LibError.InvalidAmount(0, 1);
        if (amountToWithdraw > collateral) revert LibError.InvalidAmount(amountToWithdraw, collateral);

        // If not enough collat to withdraw, use FL to repay debt
        if (safeWithdrawAmount < amountToWithdraw) {
            // total debt to repay = (Debt needed to be repayed to withdraw user amount) / (1 - safeLtv)
            uint debtToRepay = (safeDebtForCollateral(amountToWithdraw - safeWithdrawAmount, SAFE_LTV_TARGET) * 10000) /
                (10000 - SAFE_LTV_TARGET);

            console.log('debtToRepay before', debtToRepay);

            debtToRepay = (debtToRepay * (10000 + aavePool.FLASHLOAN_PREMIUM_TOTAL())) / 10000;

            console.log('debtToRepay after', debtToRepay);

            address[] memory assets = new address[](1);
            assets[0] = native;

            uint[] memory amounts = new uint[](1);
            amounts[0] = debtToRepay;

            uint[] memory interestRateModes = new uint[](1);
            interestRateModes[0] = 0;
            // 0: no open debt. (amount+fee must be paid in this case or revert)
            // 1: stable mode debt
            // 2: variable mode debt

            bytes memory params = abi.encode(ACTION.WITHDRAW, amountToWithdraw);

            console.log('flashloan...');

            aavePool.flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, referralCode);
        } else {
            console.log('withdrawing directly from pool...');

            uint amtCollatToWithdraw = _getValueInStMatic((amountToWithdraw * (10000 + securityFactor)) / 10000); // account for swap fees
            _withdrawFromAavePool(amtCollatToWithdraw);
            _swapCurve(address(stMatic), amtCollatToWithdraw);
        }

        console.log('wmatic Balance after', _getContractBalance(native));
        console.log('assetToken', address(assetToken));

        assetToken.safeTransfer(_msgSender(), amountToWithdraw);

        uint256 currentLtv = getCurrentLtv();
        uint256 maxLtv = getMaxLtv();

        if (currentLtv > maxLtv) {
            revert LibError.InvalidCDR(currentLtv, maxLtv);
        }

        console.log('wmatic left in contract', _getContractBalance(native));
    }

    /// @notice Deposits the asset token Aave Pool
    /// @notice Asset tokens must be transferred to the contract first before calling this function
    /// @param depositAmount Amount to be deposited to WMATIC Pool
    function _depositToAavePool(uint256 depositAmount) internal {
        aavePool.supply(address(stMatic), depositAmount, address(this), referralCode);
    }

    /// @notice Deposits the asset token Aave Pool
    /// @notice Asset tokens must be transferred to the contract first before calling this function
    /// @param withdrawAmount Amount to be withdrawn in stMatic from WMATIC Aave Pool
    function _withdrawFromAavePool(uint256 withdrawAmount) internal {
        aavePool.withdraw(address(stMatic), withdrawAmount, address(this));
    }

    /// @notice Deposits the asset token Aave Pool
    /// @notice Asset tokens must be transferred to the contract first before calling this function
    /// @param repayAmount Amount to be repayed to WMATIC Pool
    function _repayInAavePool(uint256 repayAmount) internal {
        aavePool.repay(native, repayAmount, 2, address(this));
    }

    /// @notice Leverage stMatic position to 3.3x
    /// @dev Use Flashloan to get 3.3x collateral, borrow max debt to SAFE_LTV_TARGET and repay FL
    function _leverageUp() internal {
        uint256 currentLtv = getCurrentLtv();
        if (currentLtv >= SAFE_LTV_TARGET && currentLtv != 0) {
            revert LibError.InvalidLTV(currentLtv, SAFE_LTV_TARGET);
        }

        uint baseCollatForLoan;
        uint256 debt = getStrategyDebt();
        uint collateral = getStrategyCollateral();

        if (debt > 0) {
            uint safeCollat = safeCollateralForDebt(debt, SAFE_LTV_TARGET); // in WMATIC value
            baseCollatForLoan = collateral - safeCollat;
        } else {
            baseCollatForLoan = collateral;
        }

        uint collatIncrease = (baseCollatForLoan * 10000) / (10000 - SAFE_LTV_TARGET); // to account for swap fees and FL fee
        uint amtToFlashLoan = collatIncrease - baseCollatForLoan;

        address[] memory assets = new address[](1);
        assets[0] = native;

        uint[] memory amounts = new uint[](1);
        amounts[0] = amtToFlashLoan;

        uint[] memory interestRateModes = new uint[](1);
        interestRateModes[0] = 2; // leave fl amount as debt in strat position
        // 0: no open debt. (amount+fee must be paid in this case or revert)
        // 1: stable mode debt
        // 2: variable mode debt

        bytes memory params = abi.encode(ACTION.DEPOSIT, 0);

        aavePool.flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, referralCode);
    }

    /// @notice Remove leverage position
    /// @dev Use flashloan to repay all debt, withdraw collateral and repay FL
    function _leverageDown() internal {
        address[] memory assets = new address[](1);
        assets[0] = native;

        uint[] memory amounts = new uint[](1);
        amounts[0] = getStrategyDebt();

        uint[] memory interestRateModes = new uint[](1);
        interestRateModes[0] = 0;
        // 0: no open debt. (amount+fee must be paid in this case or revert)
        // 1: stable mode debt
        // 2: variable mode debt

        bytes memory params = abi.encode(ACTION.PANIC, 0);

        aavePool.flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, referralCode);
    }

    /// @notice Charge Strategist and Performance fees
    /// @param callFeeRecipient Address to send the callFee (if set)
    function chargeFees(address callFeeRecipient) internal override {
        if (profitFee == 0) {
            return;
        }

        _deductFees(address(assetToken), callFeeRecipient, _getContractBalance(native));
    }

    function _claimAndSwapRewardsToNative() internal returns (uint) {
        address[] memory assets = new address[](1);
        uint bal;
        address rewardToken;

        console.log('rewards', rewards.length);

        uint nativeBal = _getContractBalance(native);

        // extras
        for (uint i; i < rewards.length; ) {
            rewardToken = rewards[i].token;
            assets[0] = rewards[i].aaveToken;

            aaveIncentives.claimRewards(assets, type(uint).max, address(this), rewardToken);
            bal = IERC20(rewardToken).balanceOf(address(this));

            if (bal >= rewards[i].minAmount) {
                console.log('univ3', bal);
                address[] memory path = pathToRoute(rewards[i].toNativeRoute);
                console.log('path[0]', path[0]);
                console.log('path[1]', path[1]);
                UniV3Swap.uniV3Swap(unirouter, rewards[i].toNativeRoute, bal);
            }
            unchecked {
                ++i;
            }
        }

        return _getContractBalance(native) - nativeBal;
    }

    /// @notice Harvest the rewards earned by Vault for more collateral tokens
    /// @dev If collateral is stMatic and debt is Matic, then the only way that
    ///      the LTV changes is if stMatic/Matic price ratio changes. If LTV is
    ///      lower than TARGET, this means that the vault has made a profit because
    ///      stMatic is worth more MATIC, and debt does not change.
    /// @param callFeeRecipient Address to send the callFee (if set)
    function _harvest(address callFeeRecipient) internal override {
        uint claimed = _claimAndSwapRewardsToNative();

        console.log('Claimed Rewards', claimed);

        if (getCurrentLtv() < SAFE_LTV_TARGET) {
            // Calculate the debt that can be added from Aave
            uint256 safeDebt = safeDebtForCollateral(getStrategyCollateral(), SAFE_LTV_TARGET);
            uint debtAvailable = safeDebt - getStrategyDebt();

            // Calculate how much that debt represents in collateral that can be withdraw without leverage
            uint collatEarnedWithoutLev = (debtAvailable * (10000 - SAFE_LTV_TARGET)) / 10000; // in wmatic terms
            console.log('collatEarnedWithoutLev', collatEarnedWithoutLev);

            // This is the actual amount the vault produced, we take profit cut
            uint256 totalFee = ((collatEarnedWithoutLev + claimed) * profitFee) / MAX_FEE;

            // Withdraw from Aave the amount of the fee in stMatic
            uint collatToWithdraw = _getValueInStMatic(totalFee);
            _withdrawFromAavePool(collatToWithdraw);

            // Swap collateral to wmatic and charge fees based on contract balance
            _swapCurve(address(stMatic), collatToWithdraw);
            chargeFees(callFeeRecipient);
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////      Admin functions      ///////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Update Aave Referral code
    /// @param _referralCode Referral code registered in aave gov (0 = no ref code)
    function updateReferralCode(uint16 _referralCode) external onlyOwner {
        referralCode = _referralCode;
    }

    /// @notice Update ltv value for SAFE_LTV_LOW
    /// @param _ltv Updated loan to value ratio
    function updateSafeLtvLow(uint256 _ltv) external onlyOwner {
        SAFE_LTV_LOW = _ltv;
    }

    /// @notice Update ltv value for SAFE_LTV_TARGET
    /// @param _ltv Updated loan to value ratio
    function updateSafeLtvTarget(uint256 _ltv) external onlyOwner {
        SAFE_LTV_TARGET = _ltv;
    }

    /// @notice Update ltv value for SAFE_LTV_HIGH
    /// @param _ltv Updated loan to value ratio
    function updateSafeLtvHigh(uint256 _ltv) external onlyOwner {
        SAFE_LTV_HIGH = _ltv;
    }

    /// @dev Rescues random funds stuck that the strat can't handle.
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        if (_token == address(assetToken)) revert LibError.InvalidToken();
        IERC20(_token).safeTransfer(_msgSender(), _getContractBalance(_token));
    }

    /// @dev Unpause the contracts
    function unpause() external override onlyManager {
        _unpause();
        _giveAllowances();

        // Swap to stMatic and Deposit as collateral in Aave
        _swapCurve(native, _getContractBalance(native));
        _depositToAavePool(_getContractBalance(address(stMatic)));

        // Borrow wMatic, swap to stMatic and deposit to aave
        _leverageUp();
    }

    function panic() public override onlyManager {
        _leverageDown();
        pause();
    }

    function setRebalancer(address _rebalancer) external onlyManager {
        rebalancer = _rebalancer;
    }

    function addRewardToken(Reward calldata _reward) external onlyOwner {
        address _token = _reward.token;
        require(_token != want, '!want');
        require(_token != native, '!native');

        rewards.push(_reward);

        IERC20(_token).safeApprove(unirouter, 0);
        IERC20(_token).safeApprove(unirouter, type(uint).max);
    }

    function resetRewardTokens() external onlyManager {
        delete rewards;
    }

    function updateSecurityFactor(uint _securityFactor) external onlyManager {
        securityFactor = _securityFactor;
    }

    function managerHarvest() external override onlyManager {
        _harvest(tx.origin);
        _leverageUp();
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////      View functions      /////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Returns the current Loan to Value Ratio for WMATIC in Aave Pool
    function getCurrentLtv() public view returns (uint256) {
        (uint collatBase, uint debtBase, , , , ) = aavePool.getUserAccountData(address(this));
        if (collatBase == 0) return 0;

        return (debtBase * 10000) / collatBase;
    }

    /// @notice Returns the current Health Factor for this strategy in Aave
    function getCurrentHealthFactor() public view returns (uint256 healthFactor) {
        (, , , , , healthFactor) = aavePool.getUserAccountData(address(this));
    }

    /// @notice Returns the Debt of strategy from Aave Pool
    /// @return amtDebt WMATIC Debt of strategy
    function getStrategyDebt() public view returns (uint256 amtDebt) {
        (, , amtDebt, , , , , , ) = dataProvider.getUserReserveData(native, address(this));
    }

    /// @notice Returns the total collateral of strategy in Aave
    /// @return amtCollateral Collateral deposited (in WMATIC value)
    function getStrategyCollateral() public view returns (uint256 amtCollateral) {
        (uint collat, , , , , , , , ) = dataProvider.getUserReserveData(address(stMatic), address(this));
        return _getValueInMatic(collat);
    }

    /// @notice Returns the maximum loan to value ratio for the strategy in aave
    /// @return maxLtv Maximum loan to value ratio value
    function getMaxLtv() public view returns (uint256 maxLtv) {
        (, , , , maxLtv, ) = aavePool.getUserAccountData(address(this));
    }

    /// @notice Checks if current position is at risk of being liquidated
    /// @return isAtRisk risk status
    function checkLiquidation() public view returns (bool isAtRisk) {
        isAtRisk = getCurrentLtv() < 1e6 / getMaxLtv();
    }

    /// @notice Returns the maximum amount of asset tokens that can be deposited
    /// @return depositLimit Maximum amount of asset tokens that can be deposited to strategy
    function getMaximumDepositLimit() public pure returns (uint256 depositLimit) {
        return type(uint256).max;
    }

    /// @notice Returns the safe amount to withdraw from Aave Pool considering Debt and Collateral
    /// @return amountToWithdraw Safe amount of WMATIC to withdraw from pool
    function safeAmountToWithdraw(uint ltv) public view returns (uint256 amountToWithdraw) {
        uint debt = getStrategyDebt();

        // if no debt or ltv 0, can withdraw all collateral
        if (ltv == 0 || debt == 0) return getStrategyCollateral();

        uint256 safeCollateral = safeCollateralForDebt(debt, ltv);
        uint256 currentCollateral = getStrategyCollateral();

        if (currentCollateral > safeCollateral) {
            amountToWithdraw = currentCollateral - safeCollateral;
        } else {
            amountToWithdraw = 0;
        }
    }

    /// @notice Returns the safe Debt for collateral(passed as argument) from Aave
    /// @param collateral Amount of wmatic for which safe Debt is to be calculated
    /// @param ltv Loan to value used to calculat debt
    /// @return safeDebt Safe amount of WMATIC than can be borrowed from Aave
    function safeDebtForCollateral(uint256 collateral, uint256 ltv) public pure returns (uint256 safeDebt) {
        safeDebt = (collateral * ltv) / 10000;
    }

    /// @notice Returns the safe amount that can be borrowed from Aave for given debt(passed as argument) and ltv
    /// @param ltv used loan to value ratio for the calculation
    /// @return safeCollateral Safe amount of WMATIC tokens
    function safeCollateralForDebt(uint256 debt, uint256 ltv) public pure returns (uint256 safeCollateral) {
        return (debt * 10000) / ltv;
    }

    function balanceOfPool() public view override returns (uint256 poolBalance) {
        uint256 collateral = getStrategyCollateral(); // in wMatic value
        uint stMaticBal = _getContractBalance(address(stMatic));

        // wMatic invested in Aave + stMatic held by strat
        uint maticBalCal = collateral + (stMaticBal > 0 ? _getValueInMatic(stMaticBal) : 0);

        poolBalance = maticBalCal - getStrategyDebt();
    }

    function balanceOfWant() public view override returns (uint256 poolBalance) {
        return _getContractBalance(address(assetToken));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (address[] memory rewardTokens, uint256[] memory amtRewards) {
        address[] memory assets = new address[](1);

        for (uint i = 0; i < rewards.length; i++) {
            assets[0] = rewards[i].aaveToken;

            amtRewards[i] = aaveIncentives.getUserRewards(assets, address(this), rewards[i].token);
            rewardTokens[i] = assets[0];
        }
    }

    /// @notice Aave Data Provider contract address
    function ADDRESSES_PROVIDER() external view override returns (address) {
        return (address(dataProvider));
    }

    /// @notice Aave Main Pool contract address
    function POOL() external view override returns (address) {
        return (address(aavePool));
    }

    function pathToRoute(bytes memory _path) public pure returns (address[] memory) {
        uint numPools = _path.numPools();
        address[] memory route = new address[](numPools + 1);
        for (uint i; i < numPools; i++) {
            (address tokenA, address tokenB, ) = _path.decodeFirstPool();
            route[i] = tokenA;
            route[i + 1] = tokenB;
            _path = _path.skipToken();
        }
        return route;
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////      Public functions      //////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    function harvestWithCallFeeRecipient(address callFeeRecipient) external override whenNotPaused {
        _harvest(callFeeRecipient);
        _leverageUp();
    }

    function harvest() external override whenNotPaused {
        _harvest(tx.origin);
        _leverageUp();
    }

    /// @notice Rebalances the vault to a safe loan to value
    /// @dev If LTV is above SAFE_LTV_TARGET,
    /// then -> Take a FL to repay the excess debt
    // If LTV is below than SAFE_LTV_LOW,
    /// then -> Use FL to leverage up the position
    /// @dev only whitelisted addresses can call this function
    function rebalanceVault() public whenNotPaused {
        if (rebalancer != address(0)) require(_msgSender() == rebalancer, '!whitelisted');

        uint256 currentLtv = getCurrentLtv();
        console.log('LTV before Rebalance', currentLtv);

        // Getting risky, repay to reduce ltv
        if (currentLtv > SAFE_LTV_TARGET) {
            uint256 safeDebt = safeDebtForCollateral(getStrategyCollateral(), SAFE_LTV_TARGET);
            uint extraDebt = getStrategyDebt() - safeDebt;
            uint debtToRepay = (extraDebt * 10000) / (10000 - SAFE_LTV_TARGET);
            debtToRepay = (debtToRepay * (10000 + aavePool.FLASHLOAN_PREMIUM_TOTAL())) / 10000;

            address[] memory assets = new address[](1);
            assets[0] = native;

            uint[] memory amounts = new uint[](1);
            amounts[0] = debtToRepay;

            uint[] memory interestRateModes = new uint[](1);
            interestRateModes[0] = 0;
            // 0: no open debt. (amount+fee must be paid in this case or revert)
            // 1: stable mode debt
            // 2: variable mode debt

            bytes memory params = abi.encode(ACTION.REPAY, 0);

            // Do a FL, repay debt, withdraw safe amount of wmatic to repay FL amount
            aavePool.flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, referralCode);

            // Check updated LTV and verify
            currentLtv = getCurrentLtv();

            if (currentLtv > (SAFE_LTV_TARGET + securityFactor) && currentLtv != 0)
                revert LibError.InvalidLTV(currentLtv, SAFE_LTV_TARGET);

            console.log('Wmatic Bal after Rebalance', _getContractBalance(native) / 1 ether);

            console.log('stMatic Bal after Rebalance', _getContractBalance(address(stMatic)) / 1 ether);
        } else if (currentLtv < SAFE_LTV_LOW) {
            _harvest(tx.origin);
            _leverageUp();

            currentLtv = getCurrentLtv();
        } else {
            revert LibError.InvalidLTV(0, 0);
        }

        emit VaultRebalanced();
    }

    /// @notice Repay debt back to the Aave Pool
    /// @dev The sender must have sufficient allowance and balance
    function repayDebt(uint256 amount) public {
        IERC20(native).safeTransferFrom(_msgSender(), address(this), amount);
        _repayInAavePool(amount);
    }

    /// @notice Called by Aave Pool after flashloan funds sent
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // shhhh
        initiator;
        premiums;

        require(_msgSender() == address(aavePool), 'ONLY_AAVE_POOL');

        (ACTION action, uint amtAux) = abi.decode(params, (ACTION, uint));

        uint amtToWithdraw;

        console.log('FL Amount', amounts[0] / 1 ether);

        if (action == ACTION.DEPOSIT) {
            // Swap borrowed assets to stMatic and deposit into Aave
            uint received = _swapCurve(assets[0], amounts[0]);
            _depositToAavePool(received);
        } else {
            // 1. Repay Debt with FL amount
            _repayInAavePool(amounts[0]);

            // Used for withdraw
            if (action == ACTION.WITHDRAW) {
                uint _currentLtv = getCurrentLtv();
                console.log('currentLTV', _currentLtv);

                if (_currentLtv == 0) {
                    (amtToWithdraw, , , , , , , , ) = dataProvider.getUserReserveData(address(stMatic), address(this));
                } else {
                    uint totalMaticNeeded = amounts[0] + amtAux + premiums[0] - _getContractBalance(native);
                    amtToWithdraw = _getValueInStMatic((totalMaticNeeded * (10000 + securityFactor)) / 10000);
                }

                _currentLtv = getCurrentLtv();
                console.log('currentLTV after withdraw', _currentLtv);
            }
            if (action == ACTION.PANIC) {
                // 2. Withdraw All collateral as stMatic
                (amtToWithdraw, , , , , , , , ) = dataProvider.getUserReserveData(address(stMatic), address(this));
            }

            if (action == ACTION.REPAY) {
                uint totalMaticNeeded = amounts[0] + premiums[0] - _getContractBalance(native);
                console.log('totalMaticNeeded', totalMaticNeeded / 1 ether);
                amtToWithdraw = _getValueInStMatic((totalMaticNeeded * (10000 + securityFactor)) / 10000);
            }

            require(amtToWithdraw > 0, 'ZERO_AMOUNT');

            // 2. Withdraw max collateral as stMatic
            _withdrawFromAavePool(amtToWithdraw);

            // 3. Swap stMatic to wMatic
            _swapCurve(address(stMatic), amtToWithdraw);
        }

        return true;
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////      onlyVault functions      //////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deposits the asset token to Aave from current contract balance
    /// @dev Asset tokens must be transferred to the contract first before calling this function
    function deposit() public override whenNotPaused onlyVault {
        if (harvestOnDeposit) _harvest(tx.origin);

        // Swap to stMatic and Deposit as collateral in Aave
        _swapCurve(native, _getContractBalance(native));
        _depositToAavePool(_getContractBalance(address(stMatic)));

        // Check LTV ratio, if less than SAFE_LTV_LOW then borrow
        uint256 currentLtv = getCurrentLtv();

        if (currentLtv < SAFE_LTV_LOW) {
            // Borrow wMatic, swap to stMatic and deposit to aave
            _leverageUp();
        }
    }

    /// @notice Withdraw deposited tokens from the Vault
    function withdraw(uint256 withdrawAmount) public override whenNotPaused onlyVault {
        _withdrawFromPool(withdrawAmount);
    }

    /// @notice called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external override onlyVault {
        uint stMaticBal = _getContractBalance(address(stMatic));

        // 1. Swap all stMatic to wMatic (if any)
        if (stMaticBal > 0) _swapCurve(address(stMatic), stMaticBal);

        // 2. Deleverage, Repay Debt and Withdraw Collateral
        _leverageDown();

        require(getStrategyDebt() == 0, 'Debt');

        // 3. Withdraw wMatic to Vault
        IERC20(native).safeTransfer(vault, _getContractBalance(native));

        emit StrategyRetired(address(this));
    }

    // shhhh
    function addLiquidity() internal virtual override {}
}
