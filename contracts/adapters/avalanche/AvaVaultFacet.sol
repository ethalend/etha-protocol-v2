//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {AvaModifiers, VaultInfo, QiVaultInfo} from './AppStorage.sol';
import {IVault} from '../../interfaces/IVault.sol';
import {IERC4626} from '../../interfaces/IERC4626.sol';
import {ICompStrategy} from '../../interfaces/ICompStrategy.sol';
import {IQiStrat} from '../../interfaces/qiDao/IQiStrat.sol';

contract AvaVaultFacet is AvaModifiers {
    function getVolatileVaultInfo(IVault vault) external view returns (VaultInfo memory info) {
        info.depositToken = address(vault.underlying());
        info.rewardsToken = address(vault.target());
        info.strategy = address(vault.strat());
        info.totalDeposits = vault.calcTotalValue();
        info.lastDistribution = vault.lastDistribution();
        info.performanceFee = vault.profitFee();
        info.withdrawalFee = vault.withdrawalFee();
        info.feeRecipient = vault.feeRecipient();
        info.strategist = info.feeRecipient;
    }

    function getCompoundVaultInfo(IERC4626 vault) external view returns (VaultInfo memory info) {
        info.depositToken = vault.asset();
        info.strategy = vault.strategy();
        info.totalDeposits = vault.totalAssets();
        info.performanceFee = ICompStrategy(info.strategy).profitFee();
        info.rewardsToken = ICompStrategy(info.strategy).output();
        info.strategist = ICompStrategy(info.strategy).strategist();
        info.feeRecipient = ICompStrategy(info.strategy).ethaFeeRecipient();
        info.lastDistribution = ICompStrategy(info.strategy).lastHarvest();

        try vault.withdrawalFee() returns (uint _withdrawalFee) {
            info.withdrawalFee = _withdrawalFee;
        } catch {
            info.withdrawalFee = ICompStrategy(info.strategy).withdrawalFee();
        }
    }

    function getQiVaultInfo(IERC4626 vault) external view returns (QiVaultInfo memory info) {
        IQiStrat strat = IQiStrat(vault.strategy());

        info.stakingContract = strat.qiStakingRewards();
        info.qiToken = strat.qiToken();
        info.lpToken = strat.lpPairToken();
        info.qiVault = strat.qiVault();
        info.poolId = strat.qiVaultId();
        info.collateral = strat.getCollateralPercent();
        info.safeHigh = strat.SAFE_COLLAT_HIGH();
        info.safeLow = strat.SAFE_COLLAT_LOW();
        info.safeTarget = strat.SAFE_COLLAT_TARGET();
        info.debt = strat.getStrategyDebt();
        info.availableBorrow = strat.safeAmountToBorrow();
    }
}
