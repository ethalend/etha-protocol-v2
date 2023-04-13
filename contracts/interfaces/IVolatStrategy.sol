//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract IVolatStrategy {
    function invest() external virtual; // underlying amount must be sent from vault to strat address before

    function divest(uint256 amount) external virtual; // should send requested amount to vault directly, not less or more

    function totalYield() external virtual returns (uint256);

    function totalYield2() external view virtual returns (uint256);

    function calcTotalValue() external view virtual returns (uint256);

    function claim() external virtual returns (uint256 claimed);

    function router() external virtual returns (address);

    function outputToTarget() external virtual returns (address[] memory);

    function setSwapRoute(address[] memory) external virtual;

    function setRouter(address) external virtual;

    function rescue(address _token, address _to, uint256 _amount) external virtual;
}
