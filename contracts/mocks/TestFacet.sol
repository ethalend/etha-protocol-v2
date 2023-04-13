// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestFacet {
    event TestEvent(address something);

    function testFunc1() external {
        emit TestEvent(address(0));
    }

    function testFunc2() external {}
}
