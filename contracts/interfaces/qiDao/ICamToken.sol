// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// stake Token to earn more Token (from farming)
interface ICamToken {
    //Aave AToken address
    function Token() external returns (address);

    // Locks amToken and mints camToken (shares)
    function enter(uint256 _amount) external;

    // claim amToken by burning camToken
    function leave(uint256 _share) external;
}