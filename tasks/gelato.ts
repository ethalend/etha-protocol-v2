import { task } from 'hardhat/config';

task('gelato:volat:add', 'Add vault to gelato harvest resolver contract', async ({ vault }, { ethers, network }) => {
  try {
    let gelato;
    switch (network.name) {
      case 'polygon':
        gelato = await ethers.getContract('Gelato_Harvest_Polygon_Volat');

      case 'avalanche':
        gelato = await ethers.getContract('Gelato_Harvest_Avax_Volat');

      default:
        break;
    }

    const tx = await gelato?.addVault(vault);
    await tx.wait();

    console.log(`Vault ${vault} added to Gelato harvest resolver!`);
  } catch (error) {
    if (error instanceof Error) console.log(error.message);
  }
}).addParam('vault', 'vault address');

task(
  'gelato:volat:remove',
  'Remove vault from gelato harvest resolver contract',
  async ({ vault }, { ethers, network }) => {
    try {
      let gelato;
      switch (network.name) {
        case 'polygon':
          gelato = await ethers.getContract('Gelato_Harvest_Polygon_Volat');

        case 'avalanche':
          gelato = await ethers.getContract('Gelato_Harvest_Avax_Volat');

        default:
          break;
      }

      const tx = await gelato?.removeVault(vault);
      await tx.wait();

      console.log(`Vault ${vault} removed from Gelato harvest resolver!`);
    } catch (error) {
      if (error instanceof Error) console.log(error.message);
    }
  }
).addParam('vault', 'vault address');

task(
  'gelato:comp:add',
  'Add compounded vault to gelato harvest resolver contract',
  async ({ vault }, { ethers, network }) => {
    try {
      let gelato;
      switch (network.name) {
        case 'polygon':
          gelato = await ethers.getContract('Gelato_Harvest_Polygon_Comp');

        case 'avalanche':
          gelato = await ethers.getContract('Gelato_Harvest_Avax_Comp');

        default:
          break;
      }

      const tx = await gelato?.addVault(vault);
      await tx.wait();

      console.log(`Vault ${vault} added to Gelato harvest resolver!`);
    } catch (error) {
      if (error instanceof Error) console.log(error.message);
    }
  }
).addParam('vault', 'vault address');

task(
  'gelato:comp:remove',
  'Remove compounded vault from gelato harvest resolver contract',
  async ({ vault }, { ethers, network }) => {
    try {
      let gelato;
      switch (network.name) {
        case 'polygon':
          gelato = await ethers.getContract('Gelato_Harvest_Polygon_Comp');

        case 'avalanche':
          gelato = await ethers.getContract('Gelato_Harvest_Avax_Comp');

        default:
          break;
      }

      const tx = await gelato?.removeVault(vault);
      await tx.wait();

      console.log(`Vault ${vault} removed from Gelato harvest resolver!`);
    } catch (error) {
      if (error instanceof Error) console.log(error.message);
    }
  }
).addParam('vault', 'vault address');
