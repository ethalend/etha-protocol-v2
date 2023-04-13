import { task } from 'hardhat/config';

task('swap:fee:get', 'Get lending market withdrawal fee', async ({}, { ethers }) => {
  const zapper = await ethers.getContract('Zapper');
  const max = await zapper.MAX_FEE();
  const fee = await zapper.swapFee();

  console.log(`Swap fee is ${fee} (${(100 * fee) / max}%)`);
});

task('swap:fee:set', 'Set vault withdrawal fee', async ({ fee }, { ethers }) => {
  if (Number(fee) > 10) throw new Error('High than 10%');
  const zapper = await ethers.getContract('Zapper');
  const max = await zapper.MAX_FEE();
  const currentFee = await zapper.swapFee();

  const tx = await zapper.setSwapFee(fee);
  await tx.wait();

  console.log(`Swap changed from ${currentFee} to ${fee} (${(100 * fee) / max}%)`);
}).addParam('fee', 'withdrawal fee (10000 = 100%)');

task('vault:fee', 'Get vault withdrawal fee', async ({ vault }, { ethers }) => {
  const vaultContract = await ethers.getContractAt('IVault', vault);
  const fee = await vaultContract.withdrawalFee();
  const max = await vaultContract.MAX_FEE();

  console.log(`Vault ${vault} fee set to ${fee} (${(100 * fee) / max}%)`);
}).addParam('vault', 'vault address');

task('vault:fee:set:volat', 'Set volat vault withdrawal fee', async ({ fee, vault }, { ethers }) => {
  if (Number(fee) > 5000) throw new Error('High than 50%');
  const vaultContract = await ethers.getContractAt('IVault', vault);
  const currentFee = await vaultContract.withdrawalFee();
  const max = await vaultContract.MAX_FEE();

  const tx = await vaultContract.setWithdrawalFee(vault, fee);
  await tx.wait();

  console.log(`Vault ${vault} fee changed from ${currentFee} to ${fee} (${(100 * fee) / max}%)`);
})
  .addParam('fee', 'withdrawal fee (10000 = 100%)')
  .addParam('vault', 'volat vault address');

task('vault:fee:set:comp', 'Set comp vault withdrawal fee', async ({ fee, vault }, { ethers }) => {
  const vaultContract = await ethers.getContractAt('VRC20Vault', vault);
  const feeCap = await vaultContract.WITHDRAWAL_FEE_CAP();
  if (Number(fee) > +feeCap) throw new Error('High than cap');

  const currentFee = await vaultContract.withdrawalFee();
  const max = await vaultContract.MAX_WITHDRAWAL_FEE();

  const tx = await vaultContract.updateWithdrawalFee(vault, fee);
  await tx.wait();

  console.log(`Vault ${vault} fee changed from ${currentFee} to ${fee}(${(100 * fee) / max}%)`);
})
  .addParam('fee', 'withdrawal fee (10000 = 100%)')
  .addParam('vault', 'comp vault address');
