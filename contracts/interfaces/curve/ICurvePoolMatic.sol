// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurvePoolMatic {
    event TokenExchange(
        address indexed buyer,
        uint256 sold_id,
        uint256 tokens_sold,
        uint256 bought_id,
        uint256 tokens_bought
    );

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth
    ) external payable returns (uint256);

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function coins(uint256 arg0) external view returns (address);
}
