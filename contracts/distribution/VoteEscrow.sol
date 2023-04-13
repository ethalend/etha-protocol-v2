// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '../interfaces/IMultiFeeDistribution.sol';

contract VoteEscrow is ERC20Votes, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct LockedBalance {
        uint256 amount;
        uint256 end;
    }

    uint256 public constant MINDAYS = 30;
    uint256 public constant MAXDAYS = 3 * 365;

    uint256 public constant MAXTIME = MAXDAYS * 1 days; // 3 years
    uint256 public constant MAX_WITHDRAWAL_PENALTY = 50000; // 50%
    uint256 public constant PRECISION = 100000; // 5 decimals

    address public lockedToken;
    address public multiFeeDistribution;
    address public penaltyCollector;
    uint256 public minLockedAmount;
    uint256 public earlyWithdrawPenaltyRate;

    uint256 public supply;

    mapping(address => LockedBalance) public locked;
    mapping(address => uint256) public mintedForLock;

    /* =============== EVENTS ==================== */
    event Deposit(address indexed provider, uint256 value, uint256 locktime, uint256 timestamp);
    event Withdraw(address indexed provider, uint256 value, uint256 timestamp);
    event PenaltyCollectorSet(address indexed addr);
    event EarlyWithdrawPenaltySet(uint256 indexed penalty);
    event MinLockedAmountSet(uint256 indexed amount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _lockedToken,
        uint256 _minLockedAmount
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        lockedToken = _lockedToken;
        minLockedAmount = _minLockedAmount;
        earlyWithdrawPenaltyRate = 30000; // 30%
    }

    function setMultiFeeDistribution(address _multiFeeDistribution) external onlyOwner {
        require(multiFeeDistribution == address(0), 'VoteEscrow: the MultiFeeDistribution is already set');
        require(
            _multiFeeDistribution != address(0),
            "VoteEscrow: the MultiFeeDistribution contract can't be the address zero"
        );
        multiFeeDistribution = _multiFeeDistribution;
    }

    function create_lock(uint256 _value, uint256 _days) external {
        require(_value >= minLockedAmount, 'less than min amount');
        require(locked[_msgSender()].amount == 0, 'Withdraw old tokens first');
        require(_days >= MINDAYS, 'Voting lock can be 7 days min');
        require(_days <= MAXDAYS, 'Voting lock can be 3 years max');
        require(multiFeeDistribution != address(0), 'VoteEscrow: need to be set a multi fee distribution');
        _deposit_for(_msgSender(), _value, _days);
    }

    function increase_amount(uint256 _value) external {
        require(_value >= minLockedAmount, 'less than min amount');
        _deposit_for(_msgSender(), _value, 0);
    }

    function increase_unlock_time(uint256 _days) external {
        require(_days >= MINDAYS, 'Voting lock can be 7 days min');
        require(_days <= MAXDAYS, 'Voting lock can be 3 years max');
        _deposit_for(_msgSender(), 0, _days);
    }

    function withdraw() external nonReentrant {
        LockedBalance storage _locked = locked[_msgSender()];
        uint256 _now = block.timestamp;

        require(_locked.amount > 0, 'Nothing to withdraw');
        require(_now >= _locked.end, "The lock didn't expire");
        uint256 _amount = _locked.amount;
        _locked.end = 0;
        _locked.amount = 0;
        _burn(_msgSender(), mintedForLock[_msgSender()]);

        /**
         * @dev We simulate also the withdraw for the user, so
         * you are actually withdrawing your voting power.
         */
        IMultiFeeDistribution(multiFeeDistribution).withdraw(mintedForLock[_msgSender()], _msgSender());
        mintedForLock[_msgSender()] = 0;
        IERC20(lockedToken).safeTransfer(_msgSender(), _amount);

        emit Withdraw(_msgSender(), _amount, _now);
    }

    // This will charge PENALTY if lock is not expired yet
    function emergencyWithdraw() external nonReentrant {
        LockedBalance storage _locked = locked[_msgSender()];
        uint256 _now = block.timestamp;
        require(_locked.amount > 0, 'Nothing to withdraw');
        uint256 _amount = _locked.amount;
        if (_now < _locked.end) {
            uint256 _fee = _penalize(_amount);
            _amount = _amount - _fee;
        }
        _locked.end = 0;
        supply -= _locked.amount;
        _locked.amount = 0;
        _burn(_msgSender(), mintedForLock[_msgSender()]);

        /**
         * @dev We simulate also the withdraw for the user, so
         * you are actually withdrawing your voting power.
         */
        IMultiFeeDistribution(multiFeeDistribution).withdraw(mintedForLock[_msgSender()], _msgSender());

        mintedForLock[_msgSender()] = 0;

        IERC20(lockedToken).safeTransfer(_msgSender(), _amount);

        emit Withdraw(_msgSender(), _amount, _now);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMinLockedAmount(uint256 _minLockedAmount) external onlyOwner {
        minLockedAmount = _minLockedAmount;
        emit MinLockedAmountSet(_minLockedAmount);
    }

    function setEarlyWithdrawPenaltyRate(uint256 _earlyWithdrawPenaltyRate) external onlyOwner {
        require(_earlyWithdrawPenaltyRate <= MAX_WITHDRAWAL_PENALTY, 'withdrawal penalty is too high'); // <= 50%
        earlyWithdrawPenaltyRate = _earlyWithdrawPenaltyRate;
        emit EarlyWithdrawPenaltySet(_earlyWithdrawPenaltyRate);
    }

    function setPenaltyCollector(address _addr) external onlyOwner {
        require(_addr != address(0), 'ZERO ADDRESS');
        penaltyCollector = _addr;
        emit PenaltyCollectorSet(_addr);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function locked__of(address _addr) external view returns (uint256) {
        return locked[_addr].amount;
    }

    function locked__end(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    function voting_power_unlock_time(uint256 _value, uint256 _unlockTime) public view returns (uint256) {
        uint256 _now = block.timestamp;
        if (_unlockTime <= _now) return 0;
        uint256 _lockedSeconds = _unlockTime - _now;
        if (_lockedSeconds >= MAXTIME) {
            return _value;
        }
        return (_value * _lockedSeconds) / MAXTIME;
    }

    function voting_power_locked_days(uint256 _value, uint256 _days) public pure returns (uint256) {
        if (_days >= MAXDAYS) {
            return _value;
        }
        return (_value * _days) / MAXDAYS;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _deposit_for(address _addr, uint256 _value, uint256 _days) internal nonReentrant {
        LockedBalance storage _locked = locked[_addr];
        uint256 _now = block.timestamp;
        uint256 _amount = _locked.amount;
        uint256 _end = _locked.end;
        uint256 _vp;
        if (_amount == 0) {
            _vp = voting_power_locked_days(_value, _days);
            _locked.amount = _value;
            _locked.end = _now + _days * 1 days;
        } else if (_days == 0) {
            _vp = voting_power_unlock_time(_value, _end);
            _locked.amount = _amount + _value;
        } else {
            require(_value == 0, 'Cannot increase amount and extend lock in the same time');
            _vp = voting_power_locked_days(_amount, _days);
            _locked.end = _end + _days * 1 days;
            require(_locked.end - _now <= MAXTIME, 'Cannot extend lock to more than 3 years');
        }
        require(_vp > 0, 'No benefit to lock');
        if (_value > 0) {
            IERC20(lockedToken).safeTransferFrom(_msgSender(), address(this), _value);
        }

        _mint(_addr, _vp);
        mintedForLock[_addr] += _vp;

        /**
         * @dev We simulate the stake for the user, so
         * you are actually staking your voting power.
         */
        IMultiFeeDistribution(multiFeeDistribution).stake(_vp, _msgSender());
        supply += _value;

        emit Deposit(_addr, _locked.amount, _locked.end, _now);
    }

    function _penalize(uint256 _amount) internal returns (uint) {
        require(penaltyCollector != address(0), 'Penalty Collector is not set');
        uint256 _fee = (_amount * earlyWithdrawPenaltyRate) / PRECISION;
        IERC20(lockedToken).safeTransfer(penaltyCollector, _fee);

        return _fee;
    }

    /**
     * @dev Restricting the allowance, transfer, approve and also the transferFrom.
     */

    function allowance(address, address) public pure override returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    function approve(address, uint256) public pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}
