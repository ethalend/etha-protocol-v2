// SPDX-License-Identifier: MIT

// Standard Curvefi voting escrow interface
// We want to use a standard iface to allow compatibility
pragma solidity ^0.8.0;

interface IVotingEscrow {
    // Following are used in Fee distribution contracts e.g.
    /*
        https://etherscan.io/address/0x74c6cade3ef61d64dcc9b97490d9fbb231e4bdcc#code
    */
    // struct Point {
    //     int128 bias;
    //     int128 slope;
    //     uint256 ts;
    //     uint256 blk;
    // }

    // function user_point_epoch(address addr) external view returns (uint256);

    // function epoch() external view returns (uint256);

    // function user_point_history(address addr, uint256 loc) external view returns (Point);

    // function checkpoint() external;

    /*
    https://etherscan.io/address/0x2e57627ACf6c1812F99e274d0ac61B786c19E74f#readContract
    */
    // Gauge proxy requires the following. inherit from ERC20
    // balanceOf
    // totalSupply

    function deposit_for(address _addr, uint256 _value) external;

    function create_lock(uint256 _value, uint256 _unlock_time) external;

    function increase_amount(uint256 _value) external;

    function increase_unlock_time(uint256 _unlock_time) external;

    function withdraw() external;

    function emergencyWithdraw() external;

    // Extra required views
    function balanceOf(address) external view returns (uint256);

    function supply() external view returns (uint256);

    function minLockedAmount() external view returns (uint256);

    function earlyWithdrawPenaltyRate() external view returns (uint256);

    function MINDAYS() external view returns (uint256);

    function MAXDAYS() external view returns (uint256);

    function MAXTIME() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function locked(address) external view returns (uint256, uint256);

    function delegates(address account) external view returns (address);

    function lockedToken() external view returns (address);

    function penaltyCollector() external view returns (address);

    function multiFeeDistribution() external view returns (address);

    function delegate(address delegatee) external;

    function locked__of(address _addr) external view returns (uint256);

    function locked__end(address _addr) external view returns (uint256);

    function voting_power_unlock_time(uint256 _value, uint256 _unlockTime) external view returns (uint256);

    function voting_power_locked_days(uint256 _value, uint256 _days) external pure returns (uint256);

    // function transferOwnership(address addr) external;
}
