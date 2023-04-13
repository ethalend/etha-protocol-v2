// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract MultiFeeDistribution is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */
    struct Reward {
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        // tracks already-added balances to handle accrued interest in aToken rewards
        // for the stakingToken this value is unused and will always be 0
        uint256 balance;
    }

    struct RewardData {
        address token;
        uint256 amount;
    }

    address[] public rewardTokens;
    address public voteEscrow;
    mapping(address => Reward) public rewardData;

    // Duration that rewards are streamed over
    uint256 public constant rewardsDuration = 86400 * 7;

    // user -> reward token -> amount
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    uint256 public totalStaked;

    // Private mappings for balance data
    mapping(address => uint256) public balances;

    /* ========== ADMIN CONFIGURATION ========== */

    modifier onlyVoteEscrow() {
        require(msg.sender == voteEscrow, 'MultiFeeDistribution: not the voteEscrow contract');
        _;
    }

    // Add a new reward token to be distributed to stakers
    function addReward(address _rewardsToken) external onlyOwner {
        require(_rewardsToken != address(0), 'MultiFeeDistribution: reward address cannot be the address 0');
        require(rewardData[_rewardsToken].lastUpdateTime == 0, 'MultiFeeDistribution: reward token already added');
        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish = block.timestamp;
    }

    function setVoteEscrow(address _voteEscrow) external onlyOwner {
        require(voteEscrow == address(0), 'MultiFeeDistribution: the voteEscrow contract is already set');
        require(_voteEscrow != address(0), "MultiFeeDistribution: the voteEscrow contract can't be the address zero");
        voteEscrow = _voteEscrow;
    }

    /* ========== VIEWS ========== */

    function _rewardPerToken(address _rewardsToken, uint256 _supply) internal view returns (uint256) {
        if (_supply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }

        return
            rewardData[_rewardsToken].rewardPerTokenStored.add(
                lastTimeRewardApplicable(_rewardsToken)
                    .sub(rewardData[_rewardsToken].lastUpdateTime)
                    .mul(rewardData[_rewardsToken].rewardRate)
                    .mul(1e18)
                    .div(_supply)
            );
    }

    function _earned(
        address _user,
        address _rewardsToken,
        uint256 _balance,
        uint256 _currentRewardPerToken
    ) internal view returns (uint256) {
        return
            _balance.mul(_currentRewardPerToken.sub(userRewardPerTokenPaid[_user][_rewardsToken])).div(1e18).add(
                rewards[_user][_rewardsToken]
            );
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        uint256 periodFinish = rewardData[_rewardsToken].periodFinish;
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken(address _rewardsToken) external view returns (uint256) {
        return _rewardPerToken(_rewardsToken, totalStaked);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return rewardData[_rewardsToken].rewardRate.mul(rewardsDuration).div(1e12);
    }

    // Address and claimable amount of all reward tokens for the given account
    function claimableRewards(address account) external view returns (RewardData[] memory) {
        RewardData[] memory _rewards = new RewardData[](rewardTokens.length);
        for (uint256 i; i < _rewards.length; i++) {
            _rewards[i].token = rewardTokens[i];
            _rewards[i].amount = _earned(
                account,
                _rewards[i].token,
                balances[account],
                _rewardPerToken(rewardTokens[i], totalStaked)
            ).div(1e12);
        }

        return _rewards;
    }

    // Total balance of an account, including unlocked, locked and earned tokens
    function stakeOfUser(address user) external view returns (uint256 amount) {
        return balances[user];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // Stake tokens to receive rewards
    // Locked tokens cannot be withdrawn for lockDuration and are eligible to receive stakingReward rewards
    function stake(uint256 amount, address user) external onlyVoteEscrow {
        require(amount > 0, 'MultiFeeDistribution: Cannot stake 0');
        require(user != address(0), 'MultiFeeDistribution: Cannot be address zero');

        _updateReward(user);
        totalStaked = totalStaked.add(amount);
        balances[user] = balances[user].add(amount);

        emit Staked(user, amount);
    }

    // @TODO maybe in the future delete this, because we want to totally exit the multifee
    function withdraw(uint256 amount, address user) external onlyVoteEscrow {
        require(amount > 0, 'MultiFeeDistribution: cannot withdraw 0');
        require(user != address(0), 'MultiFeeDistribution: Cannot be address zero');

        _updateReward(user);
        balances[user] = balances[user].sub(amount);

        totalStaked = totalStaked.sub(amount);
        emit Withdrawn(user, amount);
    }

    function _getReward(address[] memory _rewardTokens, address user) internal {
        uint256 length = _rewardTokens.length;
        for (uint256 i; i < length; i++) {
            address token = _rewardTokens[i];
            uint256 reward = rewards[user][token].div(1e12);
            // for rewards, every 24 hours we check if new
            // rewards were sent to the contract or accrued via aToken interest
            Reward storage r = rewardData[token];
            uint256 periodFinish = r.periodFinish;
            require(periodFinish > 0, 'MultiFeeDistribution: Unknown reward token');

            uint256 balance = r.balance;

            if (periodFinish < block.timestamp.add(rewardsDuration - 86400)) {
                uint256 unseen = IERC20(token).balanceOf(address(this)).sub(balance);
                if (unseen > 0) {
                    _notifyReward(token, unseen);
                    balance = balance.add(unseen);
                }
            }

            r.balance = balance.sub(reward);
            if (reward == 0) continue;
            rewards[user][token] = 0;
            IERC20(token).safeTransfer(user, reward);
            emit RewardPaid(user, token, reward);
        }
    }

    // Claim all pending staking rewards
    function getReward(address[] memory _rewardTokens, address user) public {
        require(user != address(0), 'MultiFeeDistribution: user cannot be address zero');
        _updateReward(user);
        _getReward(_rewardTokens, user);
    }

    function exit(address user) external onlyVoteEscrow {
        require(user != address(0), 'MultiFeeDistribution: user cannot be address zero');
        _updateReward(user);
        uint256 amount = balances[user];
        balances[user] = 0;

        totalStaked = totalStaked.sub(amount);
        _getReward(rewardTokens, user);

        emit Withdrawn(user, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function _notifyReward(address _rewardsToken, uint256 reward) internal {
        Reward storage r = rewardData[_rewardsToken];
        if (block.timestamp >= r.periodFinish) {
            r.rewardRate = reward.mul(1e12).div(rewardsDuration);
        } else {
            uint256 remaining = r.periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(r.rewardRate).div(1e12);
            r.rewardRate = reward.add(leftover).mul(1e12).div(rewardsDuration);
        }

        r.lastUpdateTime = block.timestamp;
        r.periodFinish = block.timestamp.add(rewardsDuration);
    }

    function _updateReward(address account) internal {
        uint256 length = rewardTokens.length;

        for (uint256 i = 0; i < length; i++) {
            address token = rewardTokens[i];
            Reward storage r = rewardData[token];
            r = rewardData[token];
            uint256 rpt = _rewardPerToken(token, totalStaked);
            r.rewardPerTokenStored = rpt;
            r.lastUpdateTime = lastTimeRewardApplicable(token);

            if (account != address(this)) {
                rewards[account][token] = _earned(account, token, balances[account], rpt);
                userRewardPerTokenPaid[account][token] = rpt;
            }
        }
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 receivedAmount);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);
    event RewardsDurationUpdated(address token, uint256 newDuration);
    event Recovered(address token, uint256 amount);
}
