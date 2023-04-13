// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAdapter {
    function getCurvePool(address lpToken) external view returns (address);

    function getAToken(address token) external view returns (address);

    function getCrToken(address token) external view returns (address);
}
