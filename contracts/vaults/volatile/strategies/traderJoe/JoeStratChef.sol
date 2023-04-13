//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../VolatStrat.sol';
import '../../../../interfaces/joe/IMasterChefJoe.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract JoeStratChef is VolatStrat {
    using SafeERC20 for IERC20;

    // ==== STATE ===== //

    IERC20 public constant JOE = IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);
    address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IMasterChefJoe public constant CHEF = IMasterChefJoe(0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F);

    uint public poolId;

    // ==== INITIALIZATION ===== //

    constructor(IVault _vault, IERC20 _want, uint _poolId, address _unirouter, address[] memory _outputToTargetRoute) {
        output = IERC20(_outputToTargetRoute[0]);

        require(address(output) == CHEF.JOE(), 'ROUTE!');
        require(_outputToTargetRoute[_outputToTargetRoute.length - 1] == address(_vault.target()));

        vault = _vault;
        want = _want;
        poolId = _poolId;
        unirouter = _unirouter;
        outputToTargetRoute = _outputToTargetRoute;

        timelock = new Timelock(_msgSender(), 1 days);

        // Infite Approvals
        want.safeApprove(address(CHEF), type(uint256).max);
    }

    // ==== GETTERS ===== //

    /**
		@dev total value of LP tokens staked on Joe Master Chef
	*/
    function calcTotalValue() external view override returns (uint256) {
        (uint256 _amount, ) = CHEF.userInfo(poolId, address(this));
        return _amount;
    }

    /**
		@dev amount of claimable JOE
	*/
    function totalYield() external view override returns (uint256) {
        (uint outputBal, , , ) = CHEF.pendingTokens(poolId, address(this));

        return outputBal;
    }

    function outputToTarget() external view override returns (address[] memory) {
        return outputToTargetRoute;
    }

    // ==== MAIN FUNCTIONS ===== //

    /**
		@notice Invest LP Tokens into Chef staking contract
		@dev can only be called by the vault contract
	*/
    function invest() external override onlyVault {
        uint256 balance = want.balanceOf(address(this));
        require(balance > 0, '!BALANCE');

        CHEF.deposit(poolId, balance);
    }

    /**
		@notice Redeem LP Tokens from Quickswap staking contract
		@dev can only be called by the vault contract
		@param amount amount of LP Tokens to withdraw
	*/
    function divest(uint256 amount) public override onlyVault {
        CHEF.withdraw(poolId, amount);

        want.safeTransfer(address(vault), amount);
    }

    /**
		@notice Claim QUICK rewards from staking contract
		@dev can only be called by the vault contract
		@dev only used when harvesting
	*/
    function claim() external override onlyVault returns (uint256 claimed) {
        CHEF.deposit(poolId, 0);

        claimed = JOE.balanceOf(address(this));
        JOE.safeTransfer(address(vault), claimed);
    }

    // ==== RESCUE ===== //

    // IMPORTANT: This function can only be called by the timelock to recover any token amount including deposited cTokens
    // However, the owner of the timelock must first submit their request and wait 7 days before confirming.
    // This gives depositors a good window to withdraw before a potentially malicious escape
    // The intent is for the owner to be able to rescue funds in the case they become stuck after launch
    // However, users should not trust the owner and watch the timelock contract least once a week on Etherscan
    // In the future, the timelock contract will be destroyed and the functionality will be removed after the code gets audited
    function rescue(address _token, address _to, uint256 _amount) external override {
        require(_msgSender() == address(timelock));
        IERC20(_token).transfer(_to, _amount);
    }

    // Any tokens (other than the lpToken) that are sent here by mistake are recoverable by the vault owner
    function sweep(address _token) external {
        address owner = vault.owner();
        require(_msgSender() == owner);
        require(_token != address(want));
        IERC20(_token).transfer(owner, IERC20(_token).balanceOf(address(this)));
    }

    function setSwapRoute(address[] memory outputToTargetRoute_) external override {
        require(_msgSender() == address(timelock));
        require(outputToTargetRoute_[0] == address(JOE));
        require(outputToTargetRoute_[outputToTargetRoute_.length - 1] == address(vault.target()));

        outputToTargetRoute = outputToTargetRoute_;
    }

    function setRouter(address router_) external override onlyTimelock {
        unirouter = router_;
    }
}
