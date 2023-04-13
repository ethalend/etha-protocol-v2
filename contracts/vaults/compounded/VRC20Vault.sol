// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.4;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import {FixedPointMathLib} from '../../libs/FixedPointMathLib.sol';
import {ICompStrategy} from '../../interfaces/ICompStrategy.sol';

/// @title EIP-4626 Vault for Ethalend(https://ethalend.org/)
/// @author ETHA Labs
/// Based on the sample minimal implementation for Solidity in EIP-4626(https://eips.ethereum.org/EIPS/eip-4626)
contract VRC20Vault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////////////////
    //                          STRUCTURES                          //
    //////////////////////////////////////////////////////////////////

    struct StratCandidate {
        address implementation;
        uint256 proposedTime;
    }

    //////////////////////////////////////////////////////////////////
    //                        STATE VARIABLES                       //
    //////////////////////////////////////////////////////////////////

    /// @dev Underlying ERC20 token(asset) for the Vault
    ERC20 public immutable asset;

    /// @dev Decimals for the Vault shares
    /// Override for Openzepplin decimals value (which uses hardcoded value of 18 ¯\_(ツ)_/¯)
    uint8 private immutable _decimals;

    /// @dev Etha withdrawal fee recipient
    address public ethaFeeRecipient;

    /// @dev The last proposed strategy to switch to.
    StratCandidate public stratCandidate;

    /// @dev The strategy currently in use by the vault.
    ICompStrategy public strategy;

    /// @dev The minimum time it has to pass before a strat candidate can be approved.
    uint256 public immutable approvalDelay;

    /// @dev Used to calculate withdrawal fee (denominator)
    uint256 public immutable MAX_WITHDRAWAL_FEE = 10000;

    /// @dev Max value for fees
    uint256 public immutable WITHDRAWAL_FEE_CAP = 150; // 1.5%

    /// @dev Withdrawal fee for the Vault
    uint256 public withdrawalFee; //1% = 100

    /// @dev To store the timestamp of last user deposit
    mapping(address => uint256) public lastDeposited;

    /// @dev Minimum deposit period before which withdrawals are charged a penalty, default value is 0
    uint256 public minDepositPeriod;

    /// @dev Penalty for early withdrawal in basis points, added to `withdrawalFee` during withdrawals, default value is 0
    uint256 public earlyWithdrawalPenalty;

    /// @dev Address allowed to change withdrawal Fee
    address public keeper;

    //////////////////////////////////////////////////////////////////
    //                          EVENTS                              //
    //////////////////////////////////////////////////////////////////

    /// @dev Emitted when tokens are deposited into the Vault via the mint and deposit methods
    event Deposit(address indexed caller, address indexed ownerAddress, uint256 assets, uint256 shares);

    /// @dev Emitted when shares are withdrawn from the Vault in redeem or withdraw methods
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed ownerAddress,
        uint256 assets,
        uint256 shares
    );

    /// @dev Emitted when a new strategy implementation is proposed
    event NewStratCandidate(address implementation);

    /// @dev Emitted when a proposed implementation is accepted(after approaval delay) and live
    event UpgradeStrat(address implementation);

    /// @dev Emitted when the withdrawal fee is updated
    event WithdrawalFeeUpdated(uint256 fee);

    /// @dev Emitted when the minimum deposit period is updated
    event MinimumDepositPeriodUpdated(uint256 minPeriod);

    /// @dev Emitted when the keeper address updated
    event NewKeeper(address newKeeper);

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        ICompStrategy _strategy,
        uint256 _approvalDelay,
        uint256 _withdrawalFee,
        address _ethaFeeRecipient
    ) ERC20(_name, _symbol) {
        asset = _asset;
        _decimals = _asset.decimals();
        strategy = _strategy;
        approvalDelay = _approvalDelay;
        withdrawalFee = _withdrawalFee;
        ethaFeeRecipient = _ethaFeeRecipient;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, '!manager');
        _;
    }

    //////////////////////////////////////////////////////////////////
    //                  VIEW  ONLY FUNCTIONS                        //
    //////////////////////////////////////////////////////////////////

    /// @dev Overridden function for ERC20 decimals
    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @dev Returns the total amount of the underlying asset that is managed by Vault
    /// @return totalManagedAssets Assets managed by the vault
    function totalAssets() public view returns (uint256 totalManagedAssets) {
        uint256 vaultBalance = asset.balanceOf(address(this));
        uint256 strategyBalance = ICompStrategy(strategy).balanceOfStrategy();
        return (vaultBalance + strategyBalance);
    }

    /// @dev Function for various UIs to display the current value of one of our yield tokens.
    /// Returns an uint256 of how much underlying asset one vault share represents with decimals equal to that asset token.
    /// @return assetsPerUnitShare Asset equivalent of one vault share
    function assetsPerShare() public view returns (uint256 assetsPerUnitShare) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 10 ** _decimals;
        } else {
            return ((totalAssets() * 10 ** _decimals) / supply);
        }
    }

    /// @dev The amount of shares that the Vault would exchange for the amount of assets provided, in an ideal scenario where all the conditions are met
    /// @param assets Amount of underlying tokens
    /// @return shares Vault shares representing equivalent deposited asset
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        // return (assets * 10**_decimals) / assetsPerShare();
        uint256 supply = totalSupply();
        if (supply == 0) {
            shares = assets;
        } else {
            shares = assets.mulDivDown(supply, totalAssets());
        }
    }

    /// @dev The amount of assets that the Vault would exchange for the amount of shares provided, in an ideal scenario where all the conditions are met
    /// @param shares Amount of Vault shares
    /// @return assets Equivalent amount of asset tokens for shares
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        // return (shares * assetsPerShare()) / 10**_decimals;
        uint256 supply = totalSupply();
        if (supply == 0) {
            assets = shares;
        } else {
            assets = shares.mulDivDown(totalAssets(), supply);
        }
    }

    /// @dev Returns aximum amount of the underlying asset that can be deposited into the Vault for the receiver, through a deposit call
    /// @param receiver Receiver address
    /// @return maxAssets The maximum amount of assets that can be deposited
    function maxDeposit(address receiver) public view returns (uint256 maxAssets) {
        (receiver);
        maxAssets = strategy.getMaximumDepositLimit();
    }

    /// @dev Returns aximum amount of shares that can be minted from the Vault for the receiver, through a mint call.
    /// @param receiver Receiver address
    /// @return maxShares The maximum amount of shares that can be minted
    function maxMint(address receiver) public view returns (uint256 maxShares) {
        (receiver);
        uint256 depositLimit = strategy.getMaximumDepositLimit();
        maxShares = convertToShares(depositLimit);
    }

    /// @dev Returns aximum amount of the underlying asset that can be withdrawn from the owner balance in the Vault, through a withdraw call
    /// @param ownerAddress Owner address of the shares
    /// @return maxAssets The maximum amount of assets that can be withdrawn
    function maxWithdraw(address ownerAddress) public view returns (uint256 maxAssets) {
        return convertToAssets(balanceOf(ownerAddress));
    }

    /// @dev Returns maximum amount of Vault shares that can be redeemed from the owner balance in the Vault, through a redeem call.
    /// @param ownerAddress Owner address
    /// @return maxShares The maximum amount of shares that can be minted
    function maxRedeem(address ownerAddress) public view returns (uint256 maxShares) {
        return balanceOf(ownerAddress);
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given current on-chain conditions.
    /// @param assets Amount of underlying tokens
    /// @return shares Equivalent amount of shares received on deposit
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        return convertToShares(assets);
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given current on-chain conditions.
    /// @param shares Amount of vault tokens to mint
    /// @return assets Equivalent amount of assets required for mint
    function previewMint(uint256 shares) public view returns (uint256 assets) {
        // return (shares * assetsPerShare()) / 10**_decimals;
        uint256 supply = totalSupply();
        if (supply == 0) {
            assets = shares;
        } else {
            assets = shares.mulDivUp(totalAssets(), supply);
        }
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block, given current on-chain conditions.
    /// @param assets Amount of underlying tokens to withdraw
    /// @return shares Equivalent amount of shares burned during withdraw
    function previewWithdraw(uint256 assets) public view virtual returns (uint256 shares) {
        // return (assets * 10**_decimals) / assetsPerShare();
        uint256 supply = totalSupply();
        if (supply == 0) {
            shares = assets;
        } else {
            shares = assets.mulDivUp(supply, totalAssets());
        }
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block, given current on-chain conditions.
    /// @param shares Amount of vault tokens to redeem
    /// @return assets Equivalent amount of assets received on redeem
    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        return convertToAssets(shares);
    }

    //////////////////////////////////////////////////////////////////
    //                       PUBLIC FUNCTIONS                       //
    //////////////////////////////////////////////////////////////////

    /// @dev Function to send funds into the strategy and put them to work. It's primarily called
    /// by the vault's deposit() function.
    function earn() internal {
        uint256 bal = asset.balanceOf(address(this));
        asset.safeTransfer(address(strategy), bal);
        strategy.deposit();
    }

    /// @dev Mints shares Vault shares to receiver by depositing exact amount of underlying tokens
    /// @param assets Amount of underlying token deposited to the Vault
    /// @param receiver Address that will receive the vault shares
    /// @return shares Amount of vault tokens minted for assets
    function deposit(uint256 assets, address receiver) public nonReentrant returns (uint256 shares) {
        uint256 initialPool = totalAssets();
        uint256 supply = totalSupply();
        asset.safeTransferFrom(msg.sender, address(this), assets);
        earn();
        uint256 currentPool = totalAssets();
        assets = currentPool - initialPool; // Additional check for deflationary tokens
        shares = 0;
        if (supply == 0) {
            shares = assets;
        } else {
            shares = (assets * supply) / initialPool;
        }
        _mint(receiver, shares);

        lastDeposited[receiver] = block.timestamp;
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @dev Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens
    /// @param shares Amount of Vault share tokens to mint
    /// @param receiver Address that will receive the vault tokens
    /// @return assets Amount of underlying tokens used to mint shares
    function mint(uint256 shares, address receiver) public nonReentrant returns (uint256 assets) {
        assets = previewMint(shares);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        earn();

        _mint(receiver, shares);

        lastDeposited[receiver] = block.timestamp;
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver
    /// @param assets Amount of underlying tokens to withdraw
    /// @param receiver Address that will receive the tokens
    /// @param ownerAddress Address that holds the share tokens
    /// @return shares Amount of share tokens burned for withdraw
    function withdraw(
        uint256 assets,
        address receiver,
        address ownerAddress
    ) public nonReentrant returns (uint256 shares) {
        shares = previewWithdraw(assets);
        if (msg.sender != ownerAddress) {
            //Checks current allowance and reverts if not enough allowance is available.
            _spendAllowance(ownerAddress, msg.sender, shares);
        }
        _burn(ownerAddress, shares);

        uint256 finalAmount = assets;
        uint256 balanceBefore = asset.balanceOf(address(this));
        if (balanceBefore < assets) {
            uint256 amountToWithdraw = assets - balanceBefore;
            strategy.withdraw(amountToWithdraw);
            uint256 balanceAfter = asset.balanceOf(address(this));
            uint256 diff = balanceAfter - balanceBefore;
            if (diff < amountToWithdraw) {
                finalAmount = balanceBefore + diff;
            }
        }
        uint256 withdrawalFeeAmount;
        if (withdrawalFee > 0) {
            if ((lastDeposited[receiver] + minDepositPeriod) < block.timestamp) {
                withdrawalFeeAmount = (finalAmount * (withdrawalFee + earlyWithdrawalPenalty)) / (MAX_WITHDRAWAL_FEE);
            } else {
                withdrawalFeeAmount = (finalAmount * withdrawalFee) / (MAX_WITHDRAWAL_FEE);
            }
        }
        asset.safeTransfer(ethaFeeRecipient, withdrawalFeeAmount);
        asset.safeTransfer(receiver, finalAmount - withdrawalFeeAmount);
        emit Withdraw(msg.sender, receiver, ownerAddress, finalAmount, shares);
    }

    /// @dev Burns exactly shares from ownerAddress and sends assets of underlying tokens to receiver
    /// @param shares Amount of share tokens to burn
    /// @param receiver Address that will receive the tokens
    /// @param ownerAddress Address that holds the share tokens
    /// @return assets Amount of underlying tokens received on redeem
    function redeem(
        uint256 shares,
        address receiver,
        address ownerAddress
    ) public nonReentrant returns (uint256 assets) {
        assets = previewRedeem(shares);
        require(assets != 0, 'ZERO_ASSETS');

        if (msg.sender != ownerAddress) {
            //Checks current allowance and reverts if not enough allowance is available.
            _spendAllowance(ownerAddress, msg.sender, shares);
        }
        _burn(ownerAddress, shares);

        uint256 finalAmount = assets;
        uint256 balanceBefore = asset.balanceOf(address(this));
        if (balanceBefore < assets) {
            uint256 amountToWithdraw = assets - balanceBefore;
            strategy.withdraw(amountToWithdraw);
            uint256 balanceAfter = asset.balanceOf(address(this));
            uint256 diff = balanceAfter - balanceBefore;
            if (diff < amountToWithdraw) {
                finalAmount = balanceBefore + diff;
            }
        }
        uint256 withdrawalFeeAmount;
        if (withdrawalFee > 0) {
            if ((lastDeposited[receiver] + minDepositPeriod) < block.timestamp) {
                withdrawalFeeAmount = (finalAmount * (withdrawalFee + earlyWithdrawalPenalty)) / (MAX_WITHDRAWAL_FEE);
            } else {
                withdrawalFeeAmount = (finalAmount * withdrawalFee) / (MAX_WITHDRAWAL_FEE);
            }
        }
        asset.safeTransfer(ethaFeeRecipient, withdrawalFeeAmount);
        asset.safeTransfer(receiver, finalAmount - withdrawalFeeAmount);
        emit Withdraw(msg.sender, receiver, ownerAddress, finalAmount, shares);
    }

    //////////////////////////////////////////////////////////////////
    //                    ADMIN FUNCTIONS                           //
    //////////////////////////////////////////////////////////////////

    /// @dev Sets the candidate for the new strat to use with this vault.
    /// @param _implementation The address of the candidate strategy.
    function proposeStrat(address _implementation) external onlyOwner {
        require(address(this) == ICompStrategy(_implementation).vault(), 'Proposal not valid for this Vault');
        stratCandidate = StratCandidate({implementation: _implementation, proposedTime: block.timestamp});

        emit NewStratCandidate(_implementation);
    }

    /// @dev It switches the active strat for the strat candidate. After upgrading, the
    /// candidate implementation is set to the 0x00 address, and proposedTime to a time
    /// happening in +100 years for safety.
    function upgradeStrat() external onlyOwner {
        require(stratCandidate.implementation != address(0), 'There is no candidate');
        require((stratCandidate.proposedTime + approvalDelay) < block.timestamp, 'Delay has not passed');

        emit UpgradeStrat(stratCandidate.implementation);

        strategy.retireStrat();
        strategy = ICompStrategy(stratCandidate.implementation);
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;

        earn();
    }

    /// @dev Rescues random funds stuck that the strat can't handle.
    /// @param _token address of the token to rescue.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(asset), '!token');

        uint256 amount = ERC20(_token).balanceOf(address(this));
        ERC20(_token).safeTransfer(msg.sender, amount);
    }

    /// @dev Update withdrawal fees for Vault, can be updated both by owner or keeper
    /// @param _fee updated withdrawal fee
    function updateWithdrawalFee(uint256 _fee) external onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, 'WITHDRAWAL_FEE_CAP');
        withdrawalFee = _fee;
        emit WithdrawalFeeUpdated(_fee);
    }

    /// @dev Update withdrawal fees for early withdrawal penalty
    /// @param _fee Early withdrawal penalty fee in basis points
    function updateEarlyWithdrawalPenalty(uint256 _fee) external onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, 'WITHDRAWAL_FEE_CAP');
        earlyWithdrawalPenalty = _fee;
        emit WithdrawalFeeUpdated(_fee);
    }

    /// @dev Update minimum deposit period for early withdrawal penalty
    /// @param _minPeriod Minimum deposit period
    function updateMinimumDepositPeriod(uint256 _minPeriod) external onlyManager {
        minDepositPeriod = _minPeriod;
        emit MinimumDepositPeriodUpdated(_minPeriod);
    }

    function changeKeeper(address newKeeper) external onlyOwner {
        require(newKeeper != address(0), 'ZERO ADDRESS');

        keeper = newKeeper;
        emit NewKeeper(newKeeper);
    }
}
