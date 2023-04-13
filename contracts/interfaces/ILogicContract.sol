// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ILogicContract {
    function name() external view returns (string memory);

    function version() external view returns (uint256);
}
