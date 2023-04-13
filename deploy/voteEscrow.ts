import { toWei } from '../utils/index';
import { ethers } from 'hardhat';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const CONTRACT_NAME = 'VoteEscrow';

const func: DeployFunction = async ({ getNamedAccounts, deployments }: HardhatRuntimeEnvironment) => {
  const { deploy, get, log } = deployments;
  const { deployer, multisig } = await getNamedAccounts();

  // Min amount of ETHA when creating a lock or increasing
  const minAmount = toWei(1000);

  const etha = await get('ETHAToken');

  const result = await deploy(CONTRACT_NAME, {
    from: deployer,
    args: ['Vote Escrow ETHA', 'veETHA', etha.address, minAmount],
    log: true,
    skipIfAlreadyDeployed: true,
  });

  if (result.newlyDeployed) {
    const voteEscrow = await ethers.getContract(CONTRACT_NAME);

    log('\nSetting penalty collector\n');
    const tx = await voteEscrow.setPenaltyCollector(multisig);
    await tx.wait();
  }
};

export default func;
func.tags = [CONTRACT_NAME];
func.dependencies = ['ETHAToken'];
