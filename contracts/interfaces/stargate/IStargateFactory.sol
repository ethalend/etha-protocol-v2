// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStargateFactory {
    function getPool(uint poolId) external view returns (address);
}
