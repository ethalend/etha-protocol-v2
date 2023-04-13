// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import {UniversalERC20} from '../../../../libs/UniversalERC20.sol';
import {IUniswapV2Router} from '../../../../interfaces/common/IUniswapV2Router.sol';
import {IUniswapV2ERC20} from '../../../../interfaces/common/IUniswapV2ERC20.sol';
import {IQiStakingRewards} from '../../../../interfaces/qiDao/IQiStakingRewards.sol';
import {IERC20StablecoinQi} from '../../../../interfaces/qiDao/IERC20StablecoinQi.sol';
import {IDelegateRegistry} from '../../../../interfaces/common/IDelegateRegistry.sol';

import {CompoundStratManager} from '../../CompoundStratManager.sol';
import {CompoundFeeManager} from '../../CompoundFeeManager.sol';

import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

import {SimpleMockOracle} from '../../../../mocks/oracles/SimpleMockOracle.sol';

contract MockStrategyQiVault is CompoundStratManager, CompoundFeeManager, ReentrancyGuard {
    using UniversalERC20 for IERC20;

    // Mock Aggregator Oracle
    SimpleMockOracle mockTokenOracle;

    // Tokens used
    IERC20 public assetToken; // Final tokens that are deposited to Qi vault: eg. BAL, camWMATIC, camWETH, LINK, etc.
    IERC20 public mai = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1); // mai token
    IERC20 public qiToken = IERC20(0x580A84C73811E1839F75d86d75d88cCa0c241fF4); //qi token

    // QiDao addresses
    IERC20StablecoinQi qiVault; // Qi Vault for Asset token
    address public qiVaultAddress; // Qi vault for asset token
    address public qiStakingRewards; //0x574Fe4E8120C4Da1741b5Fd45584de7A5b521F0F for Qi staking rewards masterchef contract
    uint256 public qiVaultId; // Vault ID

    // LP tokens and Swap paths
    address public lpToken0; //WMATIC
    address public lpToken1; //QI
    address public lpPairToken; //LP Pair token address

    address[] public maiToLp0; // MAI to WMATIC token
    address[] public maiToLp1; // MAI to QI token
    address[] public lp0ToMai; // LP0(WMATIC) to MAI
    address[] public lp1ToMai; // LP1(QI) to MAI
    address[] public lp0ToAsset; //LP0(WMATIC) to Deposit token swap Path
    address[] public lp1ToAsset; //LP1(QI) to Deposit token swap Path

    // Config variables
    uint256 public qiRewardsPid = 4; // Staking rewards pool id for WMATIC-QI
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

    constructor(
        address _assetToken,
        address _qiVaultAddress,
        address _lpToken0,
        address _lpToken1,
        address _lpPairToken,
        address _qiStakingRewards,
        CommonAddresses memory _commonAddresses
    ) CompoundStratManager(_commonAddresses) {
        assetToken = IERC20(_assetToken);
        qiVaultAddress = _qiVaultAddress;
        lpToken0 = _lpToken0;
        lpToken1 = _lpToken1;
        lpPairToken = _lpPairToken;
        qiStakingRewards = _qiStakingRewards;

        qiVault = IERC20StablecoinQi(qiVaultAddress);
        qiVaultId = qiVault.createVault();
        require(qiVault.exists(qiVaultId), 'ERR: Vault does not exists');
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////      Internal functions      //////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////

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
        require(totalMarketUSD > 0, 'ERR: Price Feed');
    }

    /// @notice Returns the LP amount equivalent of assetAmount
    /// @param assetAmount Amount of asset tokens for which equivalent LP tokens need to be calculated
    /// @return lpAmount USD equivalent of assetAmount in LP tokens
    function _getLPTokensFromAsset(uint256 assetAmount) internal view returns (uint256 lpAmount) {
        (uint256 lpTotalSupply, uint256 totalMarketUSD) = _getLPTotalMarketUSD();
        uint256 ethPriceSource = mockTokenOracle.latestAnswer(); // Asset token price
        require(ethPriceSource > 0, 'ERR: Invalid data from price source');

        // Calculations
        // usdEquivalentOfEachLp = (totalMarketUSD / totalSupply);
        // usdEquivalentOfAsset = assetAmount * ethPriceSource;
        // lpAmount = usdEquivalentOfAsset / usdEquivalentOfEachLp
        lpAmount = (assetAmount * ethPriceSource * lpTotalSupply) / (totalMarketUSD * 10 ** 8);

        // Return additional 10% of the required LP tokens to account for slippage and future withdrawals
        lpAmount = (lpAmount * 110) / 100;
    }

    /// @notice Deposits the asset token to QiVault from balance of this contract
    /// @notice Asset tokens must be transferred to the contract first before calling this function
    /// @param depositAmount AMount to be deposited to Qi Vault
    function _depositToQiVault(uint256 depositAmount) internal {
        // Deposit to QiDao vault
        assetToken.universalApprove(qiVaultAddress, depositAmount);
        IERC20StablecoinQi(qiVaultAddress).depositCollateral(qiVaultId, depositAmount);
    }

    /// @notice Borrows safe amount of MAI tokens from Qi Vault
    function _borrowTokens() internal {
        uint256 currentCollateralPercent = qiVault.checkCollateralPercentage(qiVaultId);
        require(currentCollateralPercent > SAFE_COLLAT_TARGET, 'ERR: SAFE_COLLAT_TARGET');

        uint256 amountToBorrow = safeAmountToBorrow();
        qiVault.borrowToken(qiVaultId, amountToBorrow);

        uint256 updatedCollateralPercent = qiVault.checkCollateralPercentage(qiVaultId);
        require(updatedCollateralPercent >= SAFE_COLLAT_LOW, 'ERR: SAFE_COLLAT_LOW');
        require(!qiVault.checkLiquidation(qiVaultId), 'ERR: LIQUIDATION');
    }

    /// @notice Repay MAI debt back to the qiVault
    function _repayMaiDebt() internal {
        uint256 maiDebt = qiVault.vaultDebt(qiVaultId);
        uint256 maiBalance = mai.balanceOf(address(this));

        if (maiDebt > maiBalance) {
            mai.universalApprove(qiVaultAddress, maiBalance);
            qiVault.payBackToken(qiVaultId, maiBalance);
        } else {
            mai.universalApprove(qiVaultAddress, maiDebt);
            qiVault.payBackToken(qiVaultId, maiDebt);
        }
    }

    /// @notice Swaps MAI for lpToken0 and lpToken 1 and adds liquidity to the AMM
    function _swapMaiAndAddLiquidity() internal {
        uint256 maiBalance = mai.balanceOf(address(this));
        uint256 outputHalf = maiBalance / 2;

        mai.universalApprove(unirouter, maiBalance);

        IUniswapV2Router(unirouter).swapExactTokensForTokens(outputHalf, 0, maiToLp0, address(this), block.timestamp);
        IUniswapV2Router(unirouter).swapExactTokensForTokens(outputHalf, 0, maiToLp1, address(this), block.timestamp);

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        IERC20(lpToken0).universalApprove(unirouter, lp0Bal);
        IERC20(lpToken1).universalApprove(unirouter, lp1Bal);

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

    /// @notice Deposits LP tokens to QiStaking Farm (MasterChef contract)
    /// @param amountToDeposit Amount of LP tokens to deposit to Farm
    function _depositLPToFarm(uint256 amountToDeposit) internal {
        IERC20(lpPairToken).universalApprove(qiStakingRewards, amountToDeposit);
        IQiStakingRewards(qiStakingRewards).deposit(qiRewardsPid, amountToDeposit);
    }

    /// @notice Withdraw LP tokens from QiStaking Farm and removes liquidity from AMM
    /// @param withdrawAmount Amount of LP tokens to withdraw from Farm and AMM
    function _withdrawLpAndRemoveLiquidity(uint256 withdrawAmount) internal {
        IQiStakingRewards(qiStakingRewards).withdraw(qiRewardsPid, withdrawAmount);
        uint256 lpBalance = IERC20(lpPairToken).balanceOf(address(this));
        IERC20(lpPairToken).universalApprove(address(unirouter), lpBalance);
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
        uint256 vaultCollateral = qiVault.vaultCollateral(qiVaultId);

        require(amountToWithdraw > 0, 'ERR: Invalid amount');
        require(vaultCollateral >= amountToWithdraw, 'ERR: Amount too high');

        uint256 safeWithdrawAmount = safeAmountToWithdraw();

        if (safeWithdrawAmount > amountToWithdraw) {
            // Withdraw collateral completely from qiVault
            qiVault.withdrawCollateral(qiVaultId, amountToWithdraw);
            require(qiVault.checkCollateralPercentage(qiVaultId) >= SAFE_COLLAT_LOW, 'ERR: SAFE_COLLAT_LOW');
            assetToken.universalTransfer(msg.sender, amountToWithdraw);
            return;
        } else {
            // Withdraw partially from qiVault and remaining from LP
            uint256 amountFromQiVault = safeWithdrawAmount;
            uint256 amountFromLP = amountToWithdraw - safeWithdrawAmount;

            //1. Withdraw from qi Vault
            if (amountFromQiVault > 0) {
                qiVault.withdrawCollateral(qiVaultId, amountFromQiVault);
                require(qiVault.checkCollateralPercentage(qiVaultId) >= SAFE_COLLAT_LOW, 'ERR: SAFE_COLLAT_LOW');
            }

            //2. Withdraw from LP
            uint256 lpAmount = _getLPTokensFromAsset(amountFromLP);
            _withdrawLpAndRemoveLiquidity(lpAmount);

            //3. Swap WMATIC tokens for asset tokens
            uint256 lp0Balance = IERC20(lpToken0).balanceOf(address(this));
            IERC20(lpToken0).universalApprove(address(unirouter), lp0Balance);
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                lp0Balance,
                1,
                lp0ToAsset,
                address(this),
                block.timestamp
            );

            //4. Swap Qi tokens for asset tokens
            uint256 lp1Balance = IERC20(lpToken1).balanceOf(address(this));
            IERC20(lpToken1).universalApprove(address(unirouter), lp1Balance);
            IUniswapV2Router(unirouter).swapExactTokensForTokens(
                lp1Balance,
                1,
                lp1ToAsset,
                address(this),
                block.timestamp
            );
            assetToken.universalTransfer(msg.sender, amountToWithdraw);
        }
    }

    /// @notice Charge Strategist and Performance fees
    /// @param callFeeRecipient Address to send the callFee (if set)
    function _chargeFees(address callFeeRecipient) internal {
        uint256 assetBal = assetToken.balanceOf(address(this));

        uint256 totalFee = (assetBal * profitFee) / MAX_FEE;
        uint256 callFeeAmount;
        uint256 strategistFeeAmount;

        if (callFee > 0) {
            callFeeAmount = (totalFee * callFee) / MAX_FEE;
            assetToken.universalTransfer(callFeeRecipient, callFeeAmount);
            emit CallFeeCharged(callFeeRecipient, callFeeAmount);
        }

        if (strategistFee > 0) {
            strategistFeeAmount = (totalFee * strategistFee) / MAX_FEE;
            assetToken.universalTransfer(strategist, strategistFeeAmount);
            emit StrategistFeeCharged(strategist, strategistFeeAmount);
        }

        uint256 ethaFeeAmount = (totalFee - callFeeAmount - strategistFeeAmount);
        assetToken.universalTransfer(ethaFeeRecipient, ethaFeeAmount);
        emit ProtocolFeeCharged(ethaFeeRecipient, ethaFeeAmount);
    }

    /// @notice Harvest the rewards earned by Vault for more collateral tokens
    /// @param callFeeRecipient Address to send the callFee (if set)
    function _harvest(address callFeeRecipient) internal {
        //1. Claim accrued Qi rewards from LP farm
        _depositLPToFarm(0);

        //2. Swap Qi tokens for asset tokens
        uint256 qiBalance = qiToken.balanceOf(address(this));
        qiToken.universalApprove(unirouter, qiBalance);
        IUniswapV2Router(unirouter).swapExactTokensForTokens(qiBalance, 1, lp1ToAsset, address(this), block.timestamp);

        //3. Charge performance fee and deposit to Qi vault
        _chargeFees(callFeeRecipient);
        uint256 assetBalance = assetToken.balanceOf(address(this));
        _depositToQiVault(assetBalance);

        emit Harvested(msg.sender);
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
        require(_delegationContract != address(0), 'Invalid address');
        qiDelegationContract = _delegationContract;
        emit DelegationContractUpdated(_delegationContract);
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateMaiToLp0(address[] memory _swapPath) external onlyOwner {
        require(_swapPath.length > 1);
        emit SwapPathUpdated(maiToLp0, _swapPath);
        maiToLp0 = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateMaiToLp1(address[] memory _swapPath) external onlyOwner {
        require(_swapPath.length > 1);
        emit SwapPathUpdated(maiToLp1, _swapPath);
        maiToLp1 = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateLp0ToMai(address[] memory _swapPath) external onlyOwner {
        require(_swapPath.length > 1);
        emit SwapPathUpdated(lp0ToMai, _swapPath);
        lp0ToMai = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateLp1ToMai(address[] memory _swapPath) external onlyOwner {
        require(_swapPath.length > 1);
        emit SwapPathUpdated(lp1ToMai, _swapPath);
        lp1ToMai = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateLp0ToAsset(address[] memory _swapPath) external onlyOwner {
        require(_swapPath.length > 1);
        emit SwapPathUpdated(lp0ToAsset, _swapPath);
        lp0ToAsset = _swapPath;
    }

    /// @notice Updates the swap path route for token swaps
    /// @param _swapPath Updated swap path
    function updateLp1ToAsset(address[] memory _swapPath) external onlyOwner {
        require(_swapPath.length > 1);
        emit SwapPathUpdated(lp1ToAsset, _swapPath);
        lp1ToAsset = _swapPath;
    }

    /// @notice Update Qi Rewards Pool ID for Qi MasterChef contract
    /// @param _pid Pool ID
    function updateQiRewardsPid(uint256 _pid) external onlyOwner {
        qiRewardsPid = _pid;
    }

    /// @notice Set Chainlink price feed for LP tokens
    /// @param _token Token for which price feed needs to be set
    /// @param _feed Address of Chainlink price feed
    function setPriceFeed(address _token, address _feed) external onlyOwner {
        priceFeeds[_token] = _feed;
    }

    /// @notice Set mock oracle for token price
    /// @param _oracle Address of price feed
    function setMockTokenOracle(address _oracle) external onlyOwner {
        mockTokenOracle = SimpleMockOracle(_oracle);
    }

    /// @notice Repay Debt by liquidating LP tokens
    /// Should be used to repay MAI debt before strategy migration
    /// @param _lpAmount Amount of LP tokens to liquidate
    function repayDebtLp(uint256 _lpAmount) external onlyOwner {
        //1. Withdraw LP tokens from Farm and remove liquidity
        _withdrawLpAndRemoveLiquidity(_lpAmount);

        uint256 lp0Balance = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Balance = IERC20(lpToken1).balanceOf(address(this));
        IERC20(lpToken0).universalApprove(address(unirouter), lp0Balance);
        IERC20(lpToken1).universalApprove(address(unirouter), lp1Balance);

        //2. Swap LP tokens for MAI tokens
        IUniswapV2Router(unirouter).swapExactTokensForTokens(lp0Balance, 1, lp0ToMai, address(this), block.timestamp);
        IUniswapV2Router(unirouter).swapExactTokensForTokens(lp1Balance, 1, lp1ToMai, address(this), block.timestamp);

        //3. Repay Debt to qiVault
        _repayMaiDebt();
    }

    /// @dev Rescues random funds stuck that the strat can't handle.
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(assetToken), '!token');

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).universalTransfer(msg.sender, amount);
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

    /// @notice Returns the safe amount to borrow from qiVault considering Debt and Collateral
    /// @return amountToBorrow Safe amount of MAI to borrow from vault
    function safeAmountToBorrow() public view returns (uint256 amountToBorrow) {
        uint256 tokenPriceSource = qiVault.getTokenPriceSource(); // MAI token price
        uint256 ethPriceSource = mockTokenOracle.latestAnswer(); // Asset token price
        require(ethPriceSource > 0, 'ERR: Invalid data from price source');
        require(tokenPriceSource > 0, 'ERR: Invalid data from price source');

        uint256 currentDebtValue = qiVault.vaultDebt(qiVaultId) * tokenPriceSource;

        uint256 collateralValueTimes100 = qiVault.vaultCollateral(qiVaultId) * ethPriceSource * 100;
        uint256 targetDebtValue = collateralValueTimes100 / SAFE_COLLAT_TARGET;

        amountToBorrow = (targetDebtValue - currentDebtValue) / (tokenPriceSource);
    }

    /// @notice Returns the safe amount to withdraw from qiVault considering Debt and Collateral
    /// @return amountToWithdraw Safe amount of assetTokens to withdraw from vault
    function safeAmountToWithdraw() public view returns (uint256 amountToWithdraw) {
        uint256 ethPriceSource = mockTokenOracle.latestAnswer();
        uint256 tokenPriceSource = qiVault.getTokenPriceSource();
        require(ethPriceSource > 0, 'ERR: Invalid data from price source');
        require(tokenPriceSource > 0, 'ERR: Invalid data from price source');

        uint256 currentCollateral = qiVault.vaultCollateral(qiVaultId);
        uint256 debtValue = qiVault.vaultDebt(qiVaultId) * tokenPriceSource;

        uint256 collateralValue = ((SAFE_COLLAT_LOW + 1) * debtValue) / 100;
        uint256 amountCollateral = collateralValue / ethPriceSource;
        amountToWithdraw = currentCollateral - amountCollateral;
    }

    /// @notice Returns the safe Debt for collateral(passed as argument) from qiVault
    /// @param collateral Amount of collateral tokens for which safe Debt is to be calculated
    /// @return safeDebt Safe amount of MAI than can be borrowed from qiVault
    function safeDebtForCollateral(uint256 collateral) public view returns (uint256 safeDebt) {
        uint256 ethPriceSource = mockTokenOracle.latestAnswer();
        uint256 tokenPriceSource = qiVault.getTokenPriceSource();
        require(ethPriceSource > 0, 'ERR: Invalid data from price source');
        require(tokenPriceSource > 0, 'ERR: Invalid data from price source');

        uint256 safeDebtValue = (collateral * ethPriceSource * 100) / SAFE_COLLAT_TARGET;

        safeDebt = safeDebtValue / tokenPriceSource;
    }

    /// @notice Returns the safe collateral for debt(passed as argument) from qiVault
    /// @param debt Amount of MAI tokens for which safe collateral is to be calculated
    /// @return safeCollateral Safe amount of collateral tokens for qiVault
    function safeCollateralForDebt(uint256 debt) public view returns (uint256 safeCollateral) {
        uint256 ethPriceSource = mockTokenOracle.latestAnswer();
        uint256 tokenPriceSource = qiVault.getTokenPriceSource();
        require(ethPriceSource > 0, 'ERR: Invalid data from price source');
        require(tokenPriceSource > 0, 'ERR: Invalid data from price source');

        uint256 collateralValue = (SAFE_COLLAT_TARGET * debt * tokenPriceSource) / 100;
        safeCollateral = collateralValue / ethPriceSource;
    }

    /// @notice Deposits the asset token to QiVault from balance of this contract
    /// @dev Asset tokens must be transferred to the contract first before calling this function
    function deposit() public nonReentrant whenNotPaused {
        uint256 depositAmount = assetToken.balanceOf(address(this));
        _depositToQiVault(depositAmount);

        //Check CDR ratio, if below 220% don't borrow, else borrow
        uint256 cdr_percent = qiVault.checkCollateralPercentage(qiVaultId);
        uint256 currentCollateral = qiVault.vaultCollateral(qiVaultId);

        if (cdr_percent > SAFE_COLLAT_HIGH) {
            _borrowTokens();
            _swapMaiAndAddLiquidity();

            uint256 lpAmount = IERC20(lpPairToken).balanceOf(address(this));
            _depositLPToFarm(lpAmount);
        } else if (cdr_percent == 0 && currentCollateral != 0) {
            // Note: Special case for initial deposit(as CDR is returned 0 when Debt is 0)
            // Borrow 1 wei to initialize
            qiVault.borrowToken(qiVaultId, 1);
        }
    }

    /// @notice Withdraw deposited tokens from the Vault
    function withdraw(uint256 withdrawAmount) public nonReentrant whenNotPaused {
        _withdrawFromVault(withdrawAmount);
    }

    /// @notice Harvest the rewards earned by Vault for more assetTokens
    function harvest() external virtual {
        _harvest(tx.origin);
    }

    /// @notice Harvest the rewards earned by Vault passing external callFeeRecipient
    /// @param callFeeRecipient Address that receives the callfee
    function harvestWithCallFeeRecipient(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    /// @notice Harvest the rewards earned by Vault, can only be called by Strategy Manager
    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    /// @notice Rebalances the vault to a safe Collateral to Debt ratio
    /// @dev If Collateral to Debt ratio is below SAFE_COLLAT_LOW,
    /// then -> Withdraw lpAmount from Farm > Remove liquidity from LP > swap Qi for WMATIC > Deposit WMATIC to vault
    // If CDR is greater than SAFE_COLLAT_HIGH,
    /// then -> Borrow more MAI > Swap for Qi and WMATIC > Deposit to Quickswap LP > Deposit to Qi Farm
    function rebalanceVault(bool _shouldRepay) public nonReentrant whenNotPaused {
        uint256 cdr_percent = qiVault.checkCollateralPercentage(qiVaultId);

        if (cdr_percent < SAFE_COLLAT_TARGET) {
            // Get amount of LP tokens to sell for asset tokens
            uint256 vaultCollateral = qiVault.vaultCollateral(qiVaultId);
            uint256 vaultDebt = qiVault.vaultDebt(qiVaultId);

            uint256 safeCollateral = safeCollateralForDebt(vaultDebt);
            uint256 collateralRequired = safeCollateral - vaultCollateral;
            uint256 lpAmount = _getLPTokensFromAsset(collateralRequired);

            //1. Withdraw LP tokens from Farm and remove liquidity
            _withdrawLpAndRemoveLiquidity(lpAmount);

            uint256 lp0Balance = IERC20(lpToken0).balanceOf(address(this));
            uint256 lp1Balance = IERC20(lpToken1).balanceOf(address(this));
            IERC20(lpToken0).universalApprove(address(unirouter), lp0Balance);
            IERC20(lpToken1).universalApprove(address(unirouter), lp1Balance);

            if (_shouldRepay) {
                //2. Swap LP tokens for MAI tokens
                IUniswapV2Router(unirouter).swapExactTokensForTokens(
                    lp0Balance,
                    1,
                    lp0ToMai,
                    address(this),
                    block.timestamp
                );
                IUniswapV2Router(unirouter).swapExactTokensForTokens(
                    lp1Balance,
                    1,
                    lp1ToMai,
                    address(this),
                    block.timestamp
                );

                //3. Repay Debt to qiVault
                _repayMaiDebt();
            } else {
                //2. Swap LP tokens for asset tokens
                IUniswapV2Router(unirouter).swapExactTokensForTokens(
                    lp0Balance,
                    1,
                    lp0ToAsset,
                    address(this),
                    block.timestamp
                );
                //3. Swap LP tokens for asset tokens
                IUniswapV2Router(unirouter).swapExactTokensForTokens(
                    lp1Balance,
                    1,
                    lp1ToAsset,
                    address(this),
                    block.timestamp
                );

                //3. Deposit amount to qiVault
                uint256 assetBalance = assetToken.balanceOf(address(this));
                _depositToQiVault(assetBalance);
            }

            //4. Check updated CDR and verify
            uint256 updated_cdr = qiVault.checkCollateralPercentage(qiVaultId);
            require(updated_cdr >= SAFE_COLLAT_TARGET, 'Improper lpAmount');
        } else if (cdr_percent > SAFE_COLLAT_HIGH) {
            //1. Borrow tokens
            _borrowTokens();

            //2. Swap and add liquidity
            _swapMaiAndAddLiquidity();

            //3. Deposit LP to farm
            uint256 amountToDeposit = IERC20(lpPairToken).balanceOf(address(this));
            _depositLPToFarm(amountToDeposit);
        } else {
            revert('Vault collateral ratio already within limits');
        }
        emit VaultRebalanced();
    }

    /// @notice Repay MAI debt back to the qiVault
    /// @dev The sender must have sufficient allowance and balance
    function repayDebt(uint256 amount) public nonReentrant {
        mai.universalTransferFrom(msg.sender, address(this), amount);
        _repayMaiDebt();
    }

    /// @notice calculate the total underlying 'want' held by the strat
    /// @dev This is equivalent to the amount of assetTokens deposited in the QiDAO vault
    function balanceOfStrategy() public view returns (uint256 strategyBalance) {
        strategyBalance = qiVault.vaultCollateral(qiVaultId) + assetToken.balanceOf(address(this));
    }

    /// @notice called as part of strat migration. Sends all the available funds back to the vault.
    /// NOTE: All QiVault debt must be paid before this function is called
    function retireStrat() external nonReentrant {
        require(msg.sender == vault, '!vault');
        uint256 maiDebt = qiVault.vaultDebt(qiVaultId);
        require(maiDebt == 0, 'ERR: Please repay Debt first');

        // Withdraw asset token balance from vault and strategy
        uint256 vaultCollateral = qiVault.vaultCollateral(qiVaultId);
        qiVault.withdrawCollateral(qiVaultId, vaultCollateral);

        uint256 assetBalance = assetToken.balanceOf(address(this));
        assetToken.universalTransfer(vault, assetBalance);

        // Withdraw LP balance from staking rewards
        IQiStakingRewards qiStaking = IQiStakingRewards(qiStakingRewards);
        uint256 lpBalance = qiStaking.deposited(qiRewardsPid, address(this));
        if (lpBalance > 0) {
            qiStaking.withdraw(qiRewardsPid, lpBalance);
            IERC20(lpPairToken).universalTransfer(vault, lpBalance);
        }

        emit StrategyRetired(address(this));
    }
}
