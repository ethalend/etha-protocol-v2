// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import {IERC4626} from '../interfaces/IERC4626.sol';
import {IQiStrat} from '../interfaces/qiDao/IQiStrat.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract GelatoRebalance is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private vaults;

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        for (uint256 i = 0; i < vaults.length(); i++) {
            address _vault = getVault(i);
            IQiStrat strat = IQiStrat(IERC4626(_vault).strategy());

            uint safeLow = strat.SAFE_COLLAT_LOW();
            uint safeHigh = strat.SAFE_COLLAT_HIGH();
            uint cdr = strat.getCollateralPercent();

            canExec = cdr < safeLow || cdr > safeHigh;

            if (canExec) {
                execPayload = abi.encodeWithSelector(this.rebalance.selector, address(strat));
                break;
            }
        }
    }

    function rebalance(IQiStrat strat) external {
        strat.rebalanceVault(true);
    }

    function getVault(uint256 index) public view returns (address) {
        return vaults.at(index);
    }

    function vaultExists(address _vault) external view returns (bool) {
        return vaults.contains(_vault);
    }

    function totalVaults() external view returns (uint256) {
        return vaults.length();
    }

    // OWNER FUNCTIONS

    function addVault(address _newVault) public onlyOwner {
        require(!vaults.contains(_newVault), 'EXISTS');

        vaults.add(_newVault);
    }

    function addVaults(address[] memory _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            addVault(_vaults[i]);
        }
    }

    function removeVault(address _vault) public onlyOwner {
        require(vaults.contains(_vault), '!EXISTS');

        vaults.remove(_vault);
    }

    function removeVaults(address[] memory _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            removeVault(_vaults[i]);
        }
    }
}
