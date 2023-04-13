//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../VolatStrat.sol';
import '../../../../interfaces/qiDao/IQiStakingRewards.sol';
import '../../../../interfaces/common/IDelegateRegistry.sol';
import '../../../../utils/Timelock.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract AvaQiDaoStrat is VolatStrat {
    using SafeERC20 for IERC20;

    // ==== STATE ===== //

    IERC20 public constant QI = IERC20(0xA56F9A54880afBc30CF29bB66d2D9ADCdcaEaDD6);

    // QiDao contracts
    address public chef;
    address public qiDelegationContract;
    uint public poolId;

    // EVENTS
    event VoterUpdated(address indexed voter);
    event DelegationContractUpdated(address indexed delegationContract);

    // ==== INITIALIZATION ===== //

    constructor(
        IVault _vault,
        IERC20 _want,
        address _chef,
        uint _poolId,
        address _unirouter,
        address[] memory _outputToTargetRoute
    ) {
        output = IERC20(_outputToTargetRoute[0]);
        chef = _chef;

        require(address(output) == IQiStakingRewards(chef).erc20());
        require(_outputToTargetRoute[_outputToTargetRoute.length - 1] == address(_vault.target()));

        vault = _vault;
        want = _want;
        poolId = _poolId;
        unirouter = _unirouter;
        outputToTargetRoute = _outputToTargetRoute;

        timelock = new Timelock(_msgSender(), 1 days);

        // Infite Approvals
        want.safeApprove(chef, type(uint256).max);
    }

    // ==== GETTERS ===== //

    /**
		@dev total value of LP tokens staked on QiDao Staking Contract
	*/
    function calcTotalValue() external view override returns (uint256) {
        return IQiStakingRewards(chef).deposited(poolId, address(this));
    }

    /**
		@dev amount of claimable QI
	*/
    function totalYield() external view override returns (uint256) {
        return IQiStakingRewards(chef).pending(poolId, address(this));
    }

    function outputToTarget() external view override returns (address[] memory) {
        return outputToTargetRoute;
    }

    // ==== MAIN FUNCTIONS ===== //

    /**
		@notice Invest LP Tokens into QiDao staking contract
		@dev can only be called by the vault contract
	*/
    function invest() external override onlyVault {
        uint256 balance = want.balanceOf(address(this));
        require(balance > 0);

        IQiStakingRewards(chef).deposit(poolId, balance);
    }

    /**
		@notice Redeem LP Tokens from QiDao staking contract
		@dev can only be called by the vault contract
		@param amount amount of LP Tokens to withdraw
	*/
    function divest(uint256 amount) public override onlyVault {
        uint amtBefore = want.balanceOf(address(this));

        IQiStakingRewards(chef).withdraw(poolId, amount);

        // If there are withdrawal fees in staking contract
        uint withdrawn = want.balanceOf(address(this)) - amtBefore;

        want.safeTransfer(address(vault), withdrawn);
    }

    /**
		@notice Claim QI rewards from staking contract
		@dev can only be called by the vault contract
		@dev only used when harvesting
	*/
    function claim() external override onlyVault returns (uint256 claimed) {
        IQiStakingRewards(chef).withdraw(poolId, 0);

        claimed = QI.balanceOf(address(this));
        QI.safeTransfer(address(vault), claimed);
    }

    // ==== RESCUE ===== //

    // IMPORTANT: This function can only be called by the timelock to recover any token amount including deposited cTokens
    // However, the owner of the timelock must first submit their request and wait timelock.delay() seconds before confirming.
    // This gives depositors a good window to withdraw before a potentially malicious escape
    // The intent is for the owner to be able to rescue funds in the case they become stuck after launch
    // However, users should not trust the owner and watch the timelock contract least once a week on Etherscan
    // In the future, the timelock contract will be destroyed and the functionality will be removed after the code gets audited
    function rescue(address _token, address _to, uint256 _amount) external override onlyTimelock {
        IERC20(_token).transfer(_to, _amount);
    }

    function setSwapRoute(address[] memory outputToTargetRoute_) external override onlyTimelock {
        require(outputToTargetRoute_[0] == address(QI));
        require(outputToTargetRoute_[outputToTargetRoute_.length - 1] == address(vault.target()));

        outputToTargetRoute = outputToTargetRoute_;
    }

    function setRouter(address router_) external override onlyTimelock {
        unirouter = router_;
    }

    /// @notice Delegate Qi voting power to another address
    /// @param _id   The delegate ID
    /// @param _voter Address to delegate the votes to
    function delegateVotes(bytes32 _id, address _voter) external onlyTimelock {
        IDelegateRegistry(qiDelegationContract).setDelegate(_id, _voter);
        emit VoterUpdated(_voter);
    }

    /// @notice Updates the delegation contract for Qi token Lock
    /// @param _delegationContract Updated delegation contract address
    function updateQiDelegationContract(address _delegationContract) external onlyTimelock {
        require(_delegationContract == address(0), 'ZERO_ADDRESS');
        qiDelegationContract = _delegationContract;
        emit DelegationContractUpdated(_delegationContract);
    }
}
