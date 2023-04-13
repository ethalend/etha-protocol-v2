//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./AvaxHelpers.sol";

contract ParaswapResolverAvax is AvaxHelpers {
    using UniversalERC20 for IERC20;

    // EVENTS
    event LogSwap(address indexed user, address indexed src, address indexed dest, uint256 amount);

    /**
     * @dev internal function to charge swap fees
     */
    function _paySwapFees(IERC20 erc20, uint256 amt) internal returns (uint256 feesPaid) {
        (uint256 fee, uint256 maxFee, address feeRecipient) = getSwapFee();

        // When swap fee is 0 or sender has partner role
        if (fee == 0) return 0;

        require(feeRecipient != address(0), "ZERO ADDRESS");

        feesPaid = (amt * fee) / maxFee;
        erc20.universalTransfer(feeRecipient, feesPaid);
    }

    /**
     * @dev Swap tokens in Paraswap dex
     * @param fromToken address of the source token
     * @param destToken address of the target token
     * @param transferProxy address of proxy contract that handles token transfers
     * @param tokenAmt amount of fromTokens to swap
     * @param swapTarget paraswap swapper contract
     * @param swapData encoded function call
     * @param setId set value of tokens swapped in memory contract
     */
    function swap(
        IERC20 fromToken,
        IERC20 destToken,
        address transferProxy,
        uint256 tokenAmt,
        address swapTarget,
        bytes memory swapData,
        uint256 setId
    ) external payable {
        require(tokenAmt > 0, "ZERO AMOUNT");
        require(fromToken != destToken, "SAME ASSETS");

        uint bal = destToken.balanceOf(address(this));

        // Approve only whats needed
        fromToken.universalApprove(transferProxy, tokenAmt);

        // Execute tx on paraswap Swapper
        (bool success, bytes memory returnData) = swapTarget.call(swapData);

        // Fetch error message if tx not successful
        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (returnData.length < 68) revert();
            assembly {
                returnData := add(returnData, 0x04)
            }
            revert(abi.decode(returnData, (string)));
        }

        uint received = destToken.balanceOf(address(this)) - bal;

        assert(received > 0);

        // Pay Fees
        uint256 feesPaid = _paySwapFees(IERC20(destToken), received);

        // set destTokens received
        if (setId > 0) {
            setUint(setId, received - feesPaid);
        }

        emit LogSwap(_msgSender(), address(fromToken), address(destToken), tokenAmt);
    }
}

contract ParaswapLogicAvax is ParaswapResolverAvax {
    string public constant name = "ParaswapLogic";
    uint8 public constant version = 1;

    receive() external payable {}
}
