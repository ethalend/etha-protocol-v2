//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {Modifiers, VaultInfo, QiVaultInfo} from './AppStorage.sol';
import {IVault} from '../../interfaces/IVault.sol';
import {IERC4626} from '../../interfaces/IERC4626.sol';
import {ICompStrategy} from '../../interfaces/ICompStrategy.sol';
import {IQiStrat} from '../../interfaces/qiDao/IQiStrat.sol';

contract VaultFacet is Modifiers {
    function getVolatileVaultInfo(IVault vault) external view returns (VaultInfo memory info) {
        info.depositToken = address(vault.underlying());
        info.rewardsToken = address(vault.target());
        info.strategy = address(vault.strat());
        info.totalDeposits = vault.calcTotalValue();
        info.lastDistribution = vault.lastDistribution();

        /*
            Need to try and catch because of different vault versions
            that have the fee manager vault contract inherited. Other vaults
            use the external fee manager.
        */

        try vault.performanceFee() returns (uint _performanceFee) {
            info.performanceFee = _performanceFee;
        } catch {
            info.performanceFee = vault.profitFee();
        }

        try vault.withdrawalFee() returns (uint _withdrawalFee) {
            info.withdrawalFee = _withdrawalFee;
        } catch {}

        try vault.feeRecipient() returns (address _feeRecipient) {
            info.feeRecipient = _feeRecipient;
        } catch {}

        info.strategist = info.feeRecipient;
    }

    function getCompoundVaultInfo(IERC4626 vault) external view returns (VaultInfo memory info) {
        info.depositToken = vault.asset();
        info.strategy = vault.strategy();
        info.totalDeposits = vault.totalAssets();
        info.performanceFee = ICompStrategy(info.strategy).profitFee();

        try ICompStrategy(info.strategy).output() returns (address output) {
            info.rewardsToken = output;
        } catch {}

        try ICompStrategy(info.strategy).lastHarvest() returns (uint lastHarvest) {
            info.lastDistribution = lastHarvest;
        } catch {}

        try ICompStrategy(info.strategy).ethaFeeRecipient() returns (address _ethaFeeRecipient) {
            info.feeRecipient = _ethaFeeRecipient;
        } catch {}

        try ICompStrategy(info.strategy).strategist() returns (address _strategist) {
            info.strategist = _strategist;
        } catch {}

        try ICompStrategy(info.strategy).withdrawalFee() returns (uint _withdrawalFee) {
            info.withdrawalFee = _withdrawalFee;
        } catch {
            info.withdrawalFee = vault.withdrawalFee();
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
