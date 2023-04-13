import { toWei, increaseTime, toDays } from '../utils';

import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, deployments } from 'hardhat';

const MIN_AMOUNT = 1000;

describe('Vote Escrow', () => {
  async function deploy() {
    const [_owner, _user] = await ethers.getSigners();
    const owner = _owner.address;
    const user = _user.address;

    // Hardhat Fixture Deployments
    await deployments.fixture(['VoteEscrow', 'MultiFeeDistribution']);

    const multiFeeDistribution = await ethers.getContract('MultiFeeDistribution');
    const veETHA = await ethers.getContract('VoteEscrow');
    const etha = await ethers.getContract('ETHAToken');

    const mockToken_Factory = await ethers.getContractFactory('ERC20PresetMinterPauser');
    const mockToken = await mockToken_Factory.deploy('MOCK', 'MOCK');

    await multiFeeDistribution.setVoteEscrow(veETHA.address);
    await veETHA.setMultiFeeDistribution(multiFeeDistribution.address);

    await etha.mint(owner, toWei(10_000_000));
    await etha.mint(user, toWei(10_000_000));

    return { multiFeeDistribution, veETHA, etha, owner, user, _owner, _user, mockToken };
  }

  describe('Initial params', () => {
    it('[Should have correct deployment details]:', async () => {
      const { veETHA, etha } = await loadFixture(deploy);

      const minDays = await veETHA.MINDAYS();
      const maxDays = await veETHA.MAXDAYS();
      const precision = await veETHA.PRECISION();
      const minAmount = await veETHA.minLockedAmount();
      const lockedToken = await veETHA.lockedToken();
      const symbol = await veETHA.symbol();
      const earlyWithdrawPenaltyRate = await veETHA.earlyWithdrawPenaltyRate();

      expect(+minDays).to.equal(30);
      expect(+maxDays).to.equal(3 * 365);
      expect(+precision).to.equal(100000);
      expect(minAmount).to.equal(toWei(MIN_AMOUNT));
      expect(lockedToken).to.equal(etha.address);
      expect(symbol).to.equal('veETHA');
      expect(+earlyWithdrawPenaltyRate).to.equal(30_000);
    });

    it('[Should not be able to set a multi fee again]:', async () => {
      const { veETHA, multiFeeDistribution } = await loadFixture(deploy);

      await expect(veETHA.setMultiFeeDistribution(multiFeeDistribution.address)).to.be.revertedWith(
        'VoteEscrow: the MultiFeeDistribution is already set'
      );
    });

    it('[Should not be able to set a vote escrow contract again]:', async () => {
      const { veETHA, multiFeeDistribution } = await loadFixture(deploy);

      await expect(multiFeeDistribution.setVoteEscrow(veETHA.address)).to.be.revertedWith(
        'MultiFeeDistribution: the voteEscrow contract is already set'
      );
    });
  });

  describe('User Interactions', () => {
    it('[Should create a lock and get the veETHA tokens]:', async () => {
      const { veETHA, owner, etha } = await loadFixture(deploy);

      const oldBalance = await veETHA.balanceOf(owner);
      await etha.approve(veETHA.address, toWei(MIN_AMOUNT));
      await veETHA.create_lock(toWei(MIN_AMOUNT), 90);
      const newBalance = await veETHA.balanceOf(owner);
      expect(newBalance).to.gt(oldBalance);
      const amountLocked = await veETHA.locked__of(owner);
      const timeLocked = await veETHA.locked__end(owner);
      expect(amountLocked).to.equal(toWei(MIN_AMOUNT));
      expect(timeLocked).to.gt(0);
    });

    it('[Should increase the amount of the lock after we create a lock]:', async () => {
      const { veETHA, owner, etha } = await loadFixture(deploy);

      await etha.approve(veETHA.address, toWei(MIN_AMOUNT * 10));
      await veETHA.create_lock(toWei(MIN_AMOUNT), 90);
      const initialAmountLocked = await veETHA.locked__of(owner);
      await veETHA.increase_amount(toWei(MIN_AMOUNT));
      const actualAmountLocked = await veETHA.locked__of(owner);
      expect(initialAmountLocked).to.lt(actualAmountLocked);
    });

    it('[Should increase the time of the lock after we create a lock]:', async () => {
      const { veETHA, owner, etha } = await loadFixture(deploy);

      await etha.approve(veETHA.address, toWei(MIN_AMOUNT * 10));
      await veETHA.create_lock(toWei(MIN_AMOUNT), 90);
      const initialLockedTime = await veETHA.locked__end(owner);
      await veETHA.increase_unlock_time(90);
      const actualLockedTime = await veETHA.locked__end(owner);
      expect(actualLockedTime.sub(initialLockedTime)).to.equal(toDays(90));
    });

    it('[Should be able to withdraw after lock expires]:', async () => {
      const { veETHA, owner, etha } = await loadFixture(deploy);

      await etha.approve(veETHA.address, toWei(MIN_AMOUNT * 10));
      await veETHA.create_lock(toWei(MIN_AMOUNT), 90);
      const oldBalance = await etha.balanceOf(owner);

      await expect(veETHA.withdraw()).to.be.revertedWith("The lock didn't expire");

      await increaseTime(toDays(91));
      await veETHA.withdraw();

      const newBalance = await etha.balanceOf(owner);
      const veEthaBalance = await veETHA.balanceOf(owner);

      expect(newBalance).to.gt(oldBalance);
      expect(veEthaBalance).to.eq('0');
    });

    it('[Should do a emergency withdraw right away after we create a lock]:', async () => {
      const { veETHA, etha, user, _user } = await loadFixture(deploy);

      // before
      const oldBalance = await etha.balanceOf(user);
      await etha.connect(_user).approve(veETHA.address, toWei(MIN_AMOUNT * 10));
      await veETHA.connect(_user).create_lock(toWei(MIN_AMOUNT), 90);

      // when
      await veETHA.connect(_user).emergencyWithdraw();

      // checks
      const newBalance = await etha.balanceOf(user);
      const earlyWithdrawPenaltyRate = await veETHA.earlyWithdrawPenaltyRate();
      expect(newBalance).eq(oldBalance.sub(toWei(MIN_AMOUNT * (+earlyWithdrawPenaltyRate / 100000))));
    });

    it('[Should add multiple token rewards to the multiFeeDistribution and also check for claimable rewards]:', async () => {
      const { veETHA, multiFeeDistribution, etha, mockToken, _user, user } = await loadFixture(deploy);

      const amtETHA = 1000;
      await multiFeeDistribution.addReward(etha.address);
      await multiFeeDistribution.addReward(mockToken.address);
      await mockToken.mint(multiFeeDistribution.address, toWei(10_000_000));
      await etha.mint(multiFeeDistribution.address, toWei(10_000_000));
      await multiFeeDistribution.connect(_user).getReward([etha.address, mockToken.address], user); // updates distribution

      await etha.connect(_user).approve(veETHA.address, toWei(amtETHA));
      await veETHA.connect(_user).create_lock(toWei(amtETHA), 90);
      const actualAmountLocked = await veETHA.locked__of(user);
      expect(actualAmountLocked).gt(0);

      await increaseTime(3600 * 30);

      // Has rewards after some time
      const oldClaimableRewards0 = (await multiFeeDistribution.claimableRewards(user))[0].amount;
      const oldClaimableRewards1 = (await multiFeeDistribution.claimableRewards(user))[1].amount;
      await multiFeeDistribution.connect(_user).getReward([etha.address, mockToken.address], user);

      const rewardData = await multiFeeDistribution.rewardData(etha.address);
      const newClaimableRewards0 = (await multiFeeDistribution.claimableRewards(user))[0].amount;
      const newClaimableRewards1 = (await multiFeeDistribution.claimableRewards(user))[1].amount;

      const rewardTokens = await multiFeeDistribution.getRewardTokens();
      expect(rewardTokens[0]).eql(etha.address);
      expect(rewardTokens[1]).eql(mockToken.address);
      expect(rewardData.lastUpdateTime).to.gt(0);
      expect(oldClaimableRewards0).gt(0);
      expect(oldClaimableRewards1).gt(0);
      expect(newClaimableRewards0).eq(0);
      expect(newClaimableRewards1).eq(0);
    });
  });
});
