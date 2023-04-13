import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';

const CONTRACT_NAME = 'MultiFeeDistribution';

const func: DeployFunction = async ({ getNamedAccounts, deployments, getChainId }: HardhatRuntimeEnvironment) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  const result = await deploy(CONTRACT_NAME, {
    from: deployer,
    log: true,
    skipIfAlreadyDeployed: true,
  });

  if (result.newlyDeployed && +chainId === 137) {
    log('\nSetting addresses...\n');

    const veETHA = await ethers.getContract('VoteEscrow');
    const multiFeeDistribution = await ethers.getContract(CONTRACT_NAME);
    const etha = await ethers.getContract('ETHAToken');

    let tx = await multiFeeDistribution.setVoteEscrow(veETHA.address);
    await tx.wait();
    tx = await veETHA.setMultiFeeDistribution(multiFeeDistribution.address);
    await tx.wait();
    tx = await multiFeeDistribution.addReward(etha.address);
    await tx.wait();
  }
};

export default func;
func.tags = [CONTRACT_NAME];
func.dependencies = ['VoteEscrow'];
