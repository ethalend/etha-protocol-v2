// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IDelegateRegistry {
    function delegation(address delegator, bytes32 id) external returns (address delegate);

    function setDelegate(bytes32 id, address delegate) external;

    function clearDelegate(bytes32 id) external;
}
