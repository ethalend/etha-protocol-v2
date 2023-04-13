// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface crToken {
    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);
}

contract MultiTokenBalanceGetterCR {
    constructor(address[] memory tokens, address account) {
        uint256 len = tokens.length;

        uint256[] memory returnDatas = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            address token = tokens[i];
            if (token == address(0)) {
                returnDatas[i] = account.balance;
            } else {
                returnDatas[i] = crToken(token).balanceOf(account) * crToken(token).exchangeRateStored();
            }
        }
        bytes memory data = abi.encode(block.number, returnDatas);
        assembly {
            return(add(data, 32), data)
        }
    }
}
