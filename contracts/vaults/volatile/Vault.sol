//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '../../interfaces/IVolatStrategy.sol';
import '../../interfaces/IVault.sol';
import './DividendToken.sol';
import './FeeManagerVault.sol';
import '../../utils/Timelock.sol';
import '@openzeppelin/contracts/security/Pausable.sol';

contract Vault is FeeManagerVault, Pausable, DividendToken {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IERC20;

    // EVENTS
    event Deposit(address indexed user, uint amount);
    event Withdraw(address indexed user, uint amount);
    event Claim(address indexed user, uint amount);
    event HarvesterChanged(address newHarvester);
    event StrategyChanged(address newStrat);
    event DepositLimitUpdated(uint256 newLimit);

    IERC20Metadata public underlying;
    IERC20 public rewards;
    IVolatStrategy public strat;
    Timelock public timelock;

    address public harvester;

    // if depositLimit = 0 then there is no deposit limit
    uint256 public depositLimit;
    uint256 public lastDistribution;

    modifier onlyHarvester() {
        require(msg.sender == harvester);
        _;
    }

    constructor(
        IERC20Metadata underlying_,
        IERC20 target_,
        IERC20 rewards_,
        address harvester_,
        string memory name_,
        string memory symbol_
    ) DividendToken(target_, name_, symbol_, underlying_.decimals()) {
        underlying = underlying_;
        rewards = rewards_;
        harvester = harvester_;
        // feeRecipient = msg.sender;
        depositLimit = 20000 * (10 ** underlying_.decimals()); // 20k initial deposit limit
        timelock = new Timelock(msg.sender, 3 days);
        _pause(); // paused until a strategy is connected
    }

    function _payWithdrawalFees(uint256 amt) internal returns (uint256 feesPaid) {
        if (withdrawalFee > 0 && amt > 0) {
            require(feeRecipient != address(0), 'ZERO ADDRESS');

            feesPaid = (amt * withdrawalFee) / (MAX_FEE);

            underlying.safeTransfer(feeRecipient, feesPaid);
        }
    }

    function calcTotalValue() public view returns (uint256 underlyingAmount) {
        return strat.calcTotalValue();
    }

    function totalYield() public returns (uint256) {
        return strat.totalYield();
    }

    function deposit(uint256 amount) external whenNotPaused {
        require(amount > 0, 'ZERO-AMOUNT');

        if (depositLimit > 0) {
            // if deposit limit is 0, then there is no deposit limit
            require((totalSupply() + amount) <= depositLimit);
        }

        uint initialValue = calcTotalValue();

        underlying.safeTransferFrom(msg.sender, address(strat), amount);
        strat.invest();

        uint deposited = calcTotalValue() - initialValue;

        _mint(msg.sender, deposited);

        emit Deposit(msg.sender, deposited);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, 'ZERO-AMOUNT');

        uint initialValue = calcTotalValue();

        strat.divest(amount);

        uint withdrawn = initialValue - calcTotalValue();

        _burn(msg.sender, withdrawn);

        // Withdrawal fees
        uint feesPaid = _payWithdrawalFees(withdrawn);

        underlying.safeTransfer(msg.sender, withdrawn - feesPaid);

        emit Withdraw(msg.sender, withdrawn);
    }

    function unclaimedProfit(address user) external view returns (uint256) {
        return withdrawableDividendOf(user);
    }

    function claim() public returns (uint256 claimed) {
        claimed = withdrawDividend(msg.sender);
        emit Claim(msg.sender, claimed);
    }

    // Used to claim on behalf of certain contracts e.g. Uniswap pool
    function claimOnBehalf(address recipient) external {
        require(msg.sender == harvester || msg.sender == owner());
        withdrawDividend(recipient);
    }

    // ==== ONLY OWNER ===== //

    function pauseDeposits(bool trigger) external onlyOwner {
        if (trigger) _pause();
        else _unpause();
    }

    function changeHarvester(address harvester_) external onlyOwner {
        require(harvester_ != address(0), '!ZERO ADDRESS');

        harvester = harvester_;

        emit HarvesterChanged(harvester_);
    }

    // if limit == 0 then there is no deposit limit
    function setDepositLimit(uint256 limit) external onlyOwner {
        depositLimit = limit;

        emit DepositLimitUpdated(limit);
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by the owner
    function sweep(address _token) external onlyOwner {
        require(_token != address(target));
        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
    }

    // ==== ONLY HARVESTER ===== //

    function harvest() external onlyHarvester returns (uint256 afterFee) {
        // Divest and claim rewards
        uint256 claimed = strat.claim();

        require(claimed > 0, 'Nothing to harvest');

        if (profitFee > 0) {
            // Calculate fees on underlying
            uint256 fee = (claimed * profitFee) / (MAX_FEE);
            afterFee = claimed - fee;
            rewards.safeTransfer(feeRecipient, fee);
        } else {
            afterFee = claimed;
        }

        // Transfer rewards to harvester
        rewards.safeTransfer(harvester, afterFee);
    }

    function distribute(uint256 amount) external onlyHarvester {
        distributeDividends(amount);
        lastDistribution = block.timestamp;
    }

    // ==== ONLY TIMELOCK ===== //

    // The owner has to wait 2 days to confirm changing the strat.
    // This protects users from an upgrade to a malicious strategy
    // Users must watch the timelock contract on Etherscan for any transactions
    function setStrat(IVolatStrategy strat_, bool force) external {
        if (address(strat) != address(0)) {
            require(msg.sender == address(timelock), 'Only Timelock');
            uint256 prevTotalValue = strat.calcTotalValue();

            strat.divest(prevTotalValue);
            underlying.safeTransfer(address(strat_), underlying.balanceOf(address(this)));
            strat_.invest();

            if (!force) {
                require(strat_.calcTotalValue() >= prevTotalValue);
                require(strat.calcTotalValue() == 0);
            }
        } else {
            require(msg.sender == owner());
            _unpause();
        }
        strat = strat_;

        emit StrategyChanged(address(strat));
    }
}
