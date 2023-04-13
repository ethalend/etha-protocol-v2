import { ethers, network } from 'hardhat';

export const toWei = (num: number, dec?: number) => {
  if (dec) {
    return Number(ethers.utils.parseUnits(String(num), +dec));
  }

  return String(ethers.utils.parseEther(String(num)));
};
export const fromWei = (num: number, dec?: number) => {
  if (dec) {
    return Number(ethers.utils.formatUnits(num, +dec));
  }

  return Number(ethers.utils.formatEther(num));
};

export const formatWei = async (num: number, address: string) => {
  const dec = await getTokenDecimals(address);
  return Number(ethers.utils.formatUnits(num, dec));
};

export const getTokenDecimals = async (address: string) => {
  const contract = await ethers.getContractAt('IERC20Metadata', address);

  return Number(await contract.decimals());
};

export const getTokenSymbol = async (address: string) => {
  const contract = await ethers.getContractAt('IERC20Metadata', address);

  return await contract.symbol();
};

export const toBN = (value: number | string) => ethers.BigNumber.from(String(value));

export const timeout = function (ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
};

export const increaseTime = async (sec: number) => {
  await ethers.provider.send('evm_increaseTime', [sec]);
  await ethers.provider.send('evm_mine', []);
};

export const mineBlocks = async (amount: number) => {
  for (let i = 0; i < amount; i++) {
    await ethers.provider.send('evm_mine', []);
  }
};

// Mines any number of blocks at once, in constant time
export const mineBlocksHardhat = async (amountHex: string) => {
  await network.provider.send('hardhat_mine', [amountHex]);
};

export const currentTime = async () => {
  const { timestamp } = await ethers.provider.getBlock('');
  return timestamp;
};
export const toDays = (amt: number) => 60 * 60 * 24 * amt;

export const currentBlock = async () => {
  const { number } = await ethers.provider.getBlock('');
  return number;
};
