//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20, UniversalERC20} from "../libs/UniversalERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract NFTReceiver is ERC721Holder {
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

/**
 * @title Logic Auth
 */
contract LogicAuth is AccessControlEnumerable {
    /// @dev Constant State
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PARTNER_ROLE = keccak256("PARTNER_ROLE");

    /// @notice Map of logic proxy state
    mapping(address => bool) public enabledLogics;

    /**
     * @dev Event List
     */
    event LogicEnabled(address indexed logicAddress);
    event LogicDisabled(address indexed logicAddress);

    /**
     * @dev Throws if the logic is not authorised
     */
    modifier logicAuth(address logicAddr) {
        require(logicAddr != address(0), "ZERO-ADDRES");
        require(enabledLogics[logicAddr], "!AUTHORIZED");
        _;
    }

    /// @dev
    /// @param _logicAddress (address)
    /// @return  (bool)
    function logic(address _logicAddress) external view returns (bool) {
        return enabledLogics[_logicAddress];
    }

    /// @dev Enable logic proxy address
    /// @param _logicAddress (address)
    function enableLogic(address _logicAddress) public onlyRole(MANAGER_ROLE) {
        require(_logicAddress != address(0), "ZERO-ADDRESS");
        enabledLogics[_logicAddress] = true;
        emit LogicEnabled(_logicAddress);
    }

    /// @dev Enable multiple logic proxy addresses
    /// @param _logicAddresses (addresses)
    function enableLogicMultiple(address[] calldata _logicAddresses) external {
        for (uint256 i = 0; i < _logicAddresses.length; i++) {
            enableLogic(_logicAddresses[i]);
        }
    }

    /// @dev Disable logic proxy address
    /// @param _logicAddress (address)
    function disableLogic(address _logicAddress) public onlyRole(MANAGER_ROLE) {
        require(_logicAddress != address(0), "ZERO-ADDRESS");
        enabledLogics[_logicAddress] = false;
        emit LogicDisabled(_logicAddress);
    }

    /// @dev Disable multiple logic proxy addresses
    /// @param _logicAddresses (addresses)
    function disableLogicMultiple(address[] calldata _logicAddresses) external {
        for (uint256 i = 0; i < _logicAddresses.length; i++) {
            disableLogic(_logicAddresses[i]);
        }
    }
}

contract Memory is LogicAuth {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet checkTokens;

    mapping(uint256 => uint256) values;

    modifier onlyContract() {
        require(_msgSender() == address(this), "NO EXTERNAL CALLS");
        _;
    }

    function getUint(uint256 id) external view returns (uint256) {
        return values[id];
    }

    function setUint(uint256 id, uint256 _value) public onlyContract {
        values[id] = _value;
    }

    function addToken(address _token) public onlyContract {
        if (!checkTokens.contains(_token)) checkTokens.add(_token);
    }

    function clearTokens() internal {
        for (uint i = 0; i < checkTokens.length(); i++) {
            checkTokens.remove(checkTokens.at(i));
        }
    }
}

/**
 * @title Zapper Contract
 */
contract Zapper is Memory, NFTReceiver {
    using UniversalERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_FEE = 10000;

    uint public swapFee;
    address public feeRecipient;
    address public adapter;

    /**
     * @dev initializes admin role to deployer
     */
    constructor(address _feeRecipient, uint _swapFee) {
        feeRecipient = _feeRecipient;
        swapFee = _swapFee;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
    }

    /**
        @dev internal function in charge of executing an action
        @dev checks if the target address is allowed to be called
     */
    function _execute(address _target, bytes memory _data) internal logicAuth(_target) {
        require(_target != address(0), "target-invalid");
        assembly {
            let succeeded := delegatecall(gas(), _target, add(_data, 0x20), mload(_data), 0, 0)

            switch iszero(succeeded)
            case 1 {
                // throw if delegatecall failed
                let size := returndatasize()
                returndatacopy(0x00, 0x00, size)
                revert(0x00, size)
            }
        }
    }

    /**
        @dev internal function in charge of executing an action
     */
    function checkBalances() internal {
        for (uint i = 0; i < checkTokens.length(); i++) {
            IERC20 erc20 = IERC20(checkTokens.at(i));
            uint bal = erc20.universalBalanceOf(address(this));
            if (bal > 0) erc20.universalTransfer(_msgSender(), erc20.universalBalanceOf(address(this)));
        }

        clearTokens();
    }

    /**
        @notice main function of the zapper
        @dev executes multiple delegate calls using the internal _execute fx
        @param targets address array of the logic contracts to use
        @param datas bytes array of the encoded function calls
     */
    function execute(address[] calldata targets, bytes[] calldata datas) external payable {
        for (uint256 i = 0; i < targets.length; i++) {
            _execute(targets[i], datas[i]);
        }

        checkBalances();
    }

    /// @dev Set swap fee (1% = 100)
    /// @param _swapFee new swap fee value
    function setSwapFee(uint256 _swapFee) external onlyRole(MANAGER_ROLE) {
        swapFee = _swapFee;
    }

    /// @dev Set swap fee recipient
    /// @param _adapter address of new adapter
    function setAdapterAddress(address _adapter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        adapter = _adapter;
    }

    /// @dev Set swap fee recipient
    /// @param _feeRecipient address of new recipient
    function setFeeRecipient(address _feeRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeRecipient = _feeRecipient;
    }

    /// @dev Rescues ERC20 tokens
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(_token).universalTransfer(_msgSender(), IERC20(_token).balanceOf(address(this)));
    }

    /// @dev Rescues ERC721 tokens
    /// @param _token address of the token to rescue.
    function inCaseERC721GetStuck(address _token, uint tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC721(_token).safeTransferFrom(address(this), _msgSender(), tokenId);
    }

    /// @dev Rescues ERC1155 tokens
    /// @param _token address of the token to rescue.
    function inCaseERC1155GetStuck(address _token, uint tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC1155(_token).safeTransferFrom(
            address(this),
            _msgSender(),
            tokenId,
            IERC1155(_token).balanceOf(address(this), tokenId),
            "0x0"
        );
    }

    /// @dev Don't accept ETH deposits, use execute function
    receive() external payable {
        revert();
    }
}
