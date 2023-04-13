// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./CompoundStratManager.sol";

abstract contract CompoundFeeManager is CompoundStratManager {
    // Used to calculate final fee (denominator)
    uint256 public constant MAX_FEE = 10000;
    // Max value for fees
    uint256 public constant STRATEGIST_FEE_CAP = 2500; // 25% of profitFee
    uint256 public constant CALL_FEE_CAP = 1000; // 10% of profitFee
    uint256 public constant PROFIT_FEE_CAP = 3000; // 30% of profits

    // Initial fee values
    uint256 public strategistFee = 2500; // 25% of profitFee so 20% * 25% => 5% of profit
    uint256 public callFee = 0;
    uint256 public profitFee = 2000; // 20% of profits harvested. Etha fee is 20% - strat and call fee %

    // Events to be emitted when fees are charged
    event CallFeeCharged(address indexed callFeeRecipient, uint256 callFeeAmount);
    event StrategistFeeCharged(address indexed strategist, uint256 strategistFeeAmount);
    event ProtocolFeeCharged(address indexed ethaFeeRecipient, uint256 protocolFeeAmount);
    event NewProfitFee(uint256 fee);
    event NewCallFee(uint256 fee);
    event NewStrategistFee(uint256 fee);
    event NewFeeRecipient(address newFeeRecipient);

    function setProfitFee(uint256 _fee) public onlyManager {
        require(_fee <= PROFIT_FEE_CAP, "!cap");

        profitFee = _fee;
        emit NewProfitFee(_fee);
    }

    function setCallFee(uint256 _fee) public onlyManager {
        require(_fee <= CALL_FEE_CAP, "!cap");

        callFee = _fee;
        emit NewCallFee(_fee);
    }

    function setStrategistFee(uint256 _fee) public onlyManager {
        require(_fee <= STRATEGIST_FEE_CAP, "!cap");

        strategistFee = _fee;
        emit NewStrategistFee(_fee);
    }
}
