// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import {IHarvester} from "../interfaces/IHarvester.sol";
import {IVault} from "../interfaces/IVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract GelatoVolatile is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    event VaultAdded(address vault);
    event VaultRemoved(address vault);

    EnumerableSet.AddressSet private vaults;

    IHarvester public harvester;

    uint maxGasPrice = 150 gwei;

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        uint256 delay = harvester.delay();

        for (uint256 i = 0; i < vaults.length(); i++) {
            IVault vault = IVault(getVault(i));
            canExec = (block.timestamp >= vault.lastDistribution() + delay) && tx.gasprice <= maxGasPrice;

            if (canExec) {
                execPayload = abi.encodeWithSelector(IHarvester.harvestVault.selector, address(vault));
                break;
            }
        }
    }

    function getVault(uint256 index) public view returns (address) {
        return vaults.at(index);
    }

    function vaultExists(address _vault) public view returns (bool) {
        return vaults.contains(_vault);
    }

    function totalVaults() external view returns (uint256) {
        return vaults.length();
    }

    // OWNER FUNCTIONS

    function addVault(address _newVault) public onlyOwner {
        require(!vaults.contains(_newVault), "EXISTS");

        vaults.add(_newVault);

        emit VaultAdded(_newVault);
    }

    function addVaults(address[] memory _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            addVault(_vaults[i]);
        }
    }

    function removeVault(address _vault) public onlyOwner {
        require(vaults.contains(_vault), "!EXISTS");

        vaults.remove(_vault);

        emit VaultRemoved(_vault);
    }

    function removeVaults(address[] memory _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            removeVault(_vaults[i]);
        }
    }

    function setHarvester(IHarvester _harvester) external onlyOwner {
        harvester = _harvester;
    }

    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
        maxGasPrice = _maxGasPrice;
    }
}
