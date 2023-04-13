// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract FeeManagerVault is Ownable {
    address public feeRecipient;
    address public keeper;

    // Used to calculate final fee (denominator)
    uint256 public constant MAX_FEE = 10000;

    // Max value for fees
    uint256 public constant WITHDRAWAL_FEE_CAP = 150; // 1.5%
    uint256 public constant PROFIT_FEE_CAP = 3000; // 30%

    // Initial fee values
    uint256 public withdrawalFee = 10; // 0.1%
    uint256 public profitFee = 2000; // 20% of profits harvested

    // Events to be emitted when fees are charged
    event NewProfitFee(uint256 fee);
    event NewWithdrawalFee(uint256 fee);
    event NewFeeRecipient(address newFeeRecipient);
    event NewKeeper(address newKeeper);

    constructor() {
        feeRecipient = msg.sender;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    function setProfitFee(uint256 _fee) public onlyManager {
        require(_fee <= PROFIT_FEE_CAP, "!cap");

        profitFee = _fee;
        emit NewProfitFee(_fee);
    }

    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");

        withdrawalFee = _fee;
        emit NewWithdrawalFee(_fee);
    }

    function changeFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "ZERO ADDRESS");

        feeRecipient = newFeeRecipient;
        emit NewFeeRecipient(newFeeRecipient);
    }

    function changeKeeper(address newKeeper) external onlyOwner {
        require(newKeeper != address(0), "ZERO ADDRESS");

        keeper = newKeeper;
        emit NewKeeper(newKeeper);
    }
}
