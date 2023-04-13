//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/IZapper.sol';
import '../../interfaces/common/IWETH.sol';
import '../../libs/UniversalERC20.sol';
import '@openzeppelin/contracts/utils/Context.sol';

contract AvaxHelpers is Context {
    /** 
		@dev Address of Wrapped Matic.
	**/
    IWETH internal constant wavax = IWETH(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    /**
     * @dev get avax address
     */
    function getAddressETH() public pure returns (address eth) {
        eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

    /**
     * @dev Return swap fee and recipient
     */
    function getAdapterAddress() public view returns (address adapter) {
        return IZapper(address(this)).adapter();
    }

    /**
     * @dev Return swap fee and recipient
     */
    function getSwapFee() public view returns (uint256 fee, uint256 maxFee, address recipient) {
        IZapper zapper = IZapper(address(this));

        fee = zapper.hasRole(zapper.PARTNER_ROLE(), _msgSender()) ? 0 : zapper.swapFee();
        maxFee = zapper.MAX_FEE();
        recipient = zapper.feeRecipient();
    }

    /**
     * @dev Get Uint value from Zapper Contract.
     */
    function getUint(uint256 id) internal view returns (uint256) {
        return IZapper(address(this)).getUint(id);
    }

    /**
     * @dev Set Uint value in Zapper Contract.
     */
    function setUint(uint256 id, uint256 val) internal {
        IZapper(address(this)).setUint(id, val);
    }
}
