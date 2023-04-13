import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const CONTRACT_NAME = "ETHAToken";

const func: DeployFunction = async ({
  getNamedAccounts,
  deployments,
  getChainId,
}: HardhatRuntimeEnvironment) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  if (+chainId !== 137) {
    await deploy(CONTRACT_NAME, {
      from: deployer,
      log: true,
    });
  }
};

export default func;
func.tags = [CONTRACT_NAME];
