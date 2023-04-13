// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleMockOracle {
  uint256 public s_answer;

  function setLatestAnswer(uint256 answer) public {
    s_answer = answer;
  }

  function latestAnswer() public view returns (uint256) {
    return s_answer;
  }
}