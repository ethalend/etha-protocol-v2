// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestFacet2 {
    event TestEvent(address something);

    function testFunc1() external {
        revert();
    }

    function testFunc2() external {}

    function testFunc3() external {}
}
