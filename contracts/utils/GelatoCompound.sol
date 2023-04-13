// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import {IERC4626} from '../interfaces/IERC4626.sol';
import {ICompStrategy} from '../interfaces/ICompStrategy.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

contract GelatoCompound is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    event VaultAdded(address vault);
    event VaultRemoved(address vault);
    event Harvested(address indexed vault);

    EnumerableSet.AddressSet private vaults;

    uint public delay = 1 days;

    address public callFeeRecipient;

    uint maxGasPrice = 150 gwei;

    constructor() {
        callFeeRecipient = msg.sender;
    }

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        for (uint256 i = 0; i < vaults.length(); i++) {
            address _vault = getVault(i);
            ICompStrategy strat = ICompStrategy(IERC4626(_vault).strategy());

            canExec = (block.timestamp >= strat.lastHarvest() + delay) && tx.gasprice <= maxGasPrice;

            if (canExec) {
                execPayload = abi.encodeWithSelector(this.harvest.selector, address(strat));
                break;
            }
        }
    }

    function harvest(ICompStrategy strat) external {
        try strat.harvestWithCallFeeRecipient(callFeeRecipient) {} catch {
            // If strategy does not have first fx
            strat.harvest();
        }

        emit Harvested(strat.vault());
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

        emit VaultAdded(_newVault);
    }

    function addVaults(address[] memory _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            addVault(_vaults[i]);
        }
    }

    function removeVault(address _vault) public onlyOwner {
        require(vaults.contains(_vault), '!EXISTS');

        vaults.remove(_vault);

        emit VaultRemoved(_vault);
    }

    function removeVaults(address[] memory _vaults) external {
        for (uint256 i = 0; i < _vaults.length; i++) {
            removeVault(_vaults[i]);
        }
    }

    function setDelay(uint _delay) external onlyOwner {
        delay = _delay;
    }

    function setFeeRecipient(address _callFeeRecipient) external onlyOwner {
        callFeeRecipient = _callFeeRecipient;
    }

    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
        maxGasPrice = _maxGasPrice;
    }
}
