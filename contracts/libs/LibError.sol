//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library LibError {
    error QiVaultError();
    error PriceFeedError();
    error LiquidationRisk();
    error HarvestNotReady();
    error ZeroValue();
    error InvalidAddress();
    error InvalidToken();
    error InvalidSwapPath();
    error InvalidAmount(uint256 current, uint256 expected);
    error InvalidCDR(uint256 current, uint256 expected);
    error InvalidLTV(uint256 current, uint256 expected);
}
