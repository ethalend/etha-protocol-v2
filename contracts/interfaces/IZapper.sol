//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IZapper {
    function PARTNER_ROLE() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function adapter() external view returns (address);

    function feeRecipient() external view returns (address);

    function MAX_FEE() external view returns (uint256);

    function swapFee() external view returns (uint256);

    function getUint(uint256) external view returns (uint256);

    function setUint(uint256 id, uint256 value) external;

    function addToken(address _token) external;

    function clearTokens() external;

    function execute(address[] calldata targets, bytes[] calldata datas) external payable;

    function setSwapFee(uint256 _swapFee) external;

    function setAdapterAddress(address _adapter) external;

    function setFeeRecipient(address _feeRecipient) external;

    event LogSwap(address indexed user, address indexed src, address indexed dest, uint256 amount);
    event LogLiquidityAdd(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB
    );
    event LogLiquidityRemove(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB
    );
    event LogDeposit(address indexed user, address indexed erc20, uint256 tokenAmt);
    event LogWithdraw(address indexed user, address indexed erc20, uint256 tokenAmt);
    event VaultDeposit(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);
    event VaultWithdraw(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);
    event VaultClaim(address indexed user, address indexed vault, address indexed erc20, uint256 tokenAmt);
}
