// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';

contract CompoundStratManager is Ownable, Pausable {
    /**
     * @dev ETHA Contracts:
     * {keeper} - Address to manage a few lower risk features of the strat
     * {strategist} - Address of the strategy author/deployer where strategist fee will go.
     * {vault} - Address of the vault that controls the strategy's funds.
     * {unirouter} - Address of exchange to execute swaps.
     */
    address public keeper;
    address public strategist;
    address public unirouter;
    address public vault;
    address public ethaFeeRecipient;

    struct CommonAddresses {
        address unirouter;
        address keeper;
        address strategist;
        address ethaFeeRecipient;
    }

    /**
     * @dev Initializes the base strategy.
     * @param _commonAddresses struct of addresses
     *  _keeper address to use as alternative owner.
     *  _strategist address where strategist fees go.
     *  _unirouter router to use for swaps
     *  _ethaFeeRecipient address where to send Etha's fees.
     */
    constructor(CommonAddresses memory _commonAddresses) {
        keeper = _commonAddresses.keeper;
        strategist = _commonAddresses.strategist;
        unirouter = _commonAddresses.unirouter;
        ethaFeeRecipient = _commonAddresses.ethaFeeRecipient;

        _pause(); // until strategy is set;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, '!manager');
        _;
    }

    // checks that caller is vault contract.
    modifier onlyVault() {
        require(msg.sender == vault, '!vault');
        _;
    }

    /**
     * @dev Updates address of the strat keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0), '!ZERO ADDRESS');
        keeper = _keeper;
    }

    /**
     * @dev Updates address where strategist fee earnings will go.
     * @param _strategist new strategist address.
     */
    function setStrategist(address _strategist) external {
        require(_strategist != address(0), '!ZERO ADDRESS');
        require(msg.sender == strategist, '!strategist');
        strategist = _strategist;
    }

    /**
     * @dev Updates router that will be used for swaps.
     * @param _unirouter new unirouter address.
     */
    function setUnirouter(address _unirouter) external onlyOwner {
        require(_unirouter != address(0), '!ZERO ADDRESS');
        unirouter = _unirouter;
    }

    /**
     * @dev Updates parent vault.
     * @param _vault new vault address.
     */
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), '!ZERO ADDRESS');
        require(vault == address(0), 'vault already set');
        vault = _vault;
        _unpause();
    }

    /**
     * @dev Updates etja fee recipient.
     * @param _ethaFeeRecipient new etha fee recipient address.
     */
    function setEthaFeeRecipient(address _ethaFeeRecipient) external onlyOwner {
        require(_ethaFeeRecipient != address(0), '!ZERO ADDRESS');
        ethaFeeRecipient = _ethaFeeRecipient;
    }
}
