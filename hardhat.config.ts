import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import 'hardhat-deploy';
import env from './config';

import './tasks';

let accounts;

if (env.POLYGON_PRIVKEY) {
  accounts = [env.POLYGON_PRIVKEY];
} else {
  accounts = {
    mnemonic: 'test test test test test test test test test test test test',
  };
}

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      forking: {
        url: env.POLYGON_NODE_URL,
        blockNumber: 41_000_000,
      },
    },
    polygon: {
      url: env.POLYGON_NODE_URL,
      chainId: 137,
      accounts,
    },
  },
  namedAccounts: {
    deployer: 0,
    registryOwner: 0,
    strategist: 0,
    keeper: 0,
    diamondAdmin: 0,
    multisig: {
      default: 0,
      polygon: env.MULTISIG_ADDRESS_POLYGON,
      avalanche: env.MULTISIG_ADDRESS_AVALANCE,
    },
    feeRecipient: {
      default: 0,
      polygon: env.MULTISIG_ADDRESS_POLYGON,
      avalanche: env.MULTISIG_ADDRESS_AVALANCE,
    },
  },
  etherscan: {
    apiKey: {
      polygon: env.POLYGON_ETHERSCAN_API,
      avalanche: env.AVAX_ETHERSCAN_API,
    },
  },
  solidity: {
    version: '0.8.4',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
};

export default config;
