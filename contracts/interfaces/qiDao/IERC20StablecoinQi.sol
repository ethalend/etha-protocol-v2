// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20StablecoinQi {
    function _minimumCollateralPercentage() external returns (uint256);

    function vaultCollateral(uint256) external view returns (uint256);

    function vaultDebt(uint256) external view returns (uint256);

    function debtRatio() external returns (uint256);

    function gainRatio() external returns (uint256);

    function collateral() external view returns (address);

    function collateralDecimals() external returns (uint256);

    function maticDebt(address) external returns (uint256);

    function mai() external view returns (address);

    function minDebt() external view returns (uint256);

    function getDebtCeiling() external view returns (uint256);

    function exists(uint256 vaultID) external view returns (bool);

    function getClosingFee() external view returns (uint256);

    function getOpeningFee() external view returns (uint256);

    function getTokenPriceSource() external view returns (uint256);

    function getEthPriceSource() external view returns (uint256);

    function createVault() external returns (uint256);

    function destroyVault(uint256 vaultID) external;

    function depositCollateral(uint256 vaultID, uint256 amount) external;

    function withdrawCollateral(uint256 vaultID, uint256 amount) external;

    function borrowToken(uint256 vaultID, uint256 amount) external;

    function payBackToken(uint256 vaultID, uint256 amount) external;

    function getPaid() external;

    function checkCost(uint256 vaultID) external view returns (uint256);

    function checkExtract(uint256 vaultID) external view returns (uint256);

    function checkCollateralPercentage(uint256 vaultID) external view returns (uint256);

    function checkLiquidation(uint256 vaultID) external view returns (bool);

    function liquidateVault(uint256 vaultID) external;
}
