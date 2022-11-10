import { Contract } from 'ethers';
import { DeployFunction } from 'hardhat-deploy/types';

import { LayerZeroBridgeERC20, LayerZeroBridgeERC20__factory } from '../typechain';
import LZ_CHAINIDS from './constants/layerzeroChainIds.json';

const func: DeployFunction = async ({ ethers, network }) => {
  const { deployer } = await ethers.getNamedSigners();

  const OFTs: { [string: string]: string } = {
    optimism: '0x9201cC18965792808549566e6B06B016d915313A',
    arbitrum: '0x366CEE609A64037a4910868c5b3cd62b9D019695',
    mainnet: '0x1056178977457A5F4BE33929520455A7d2E28670',
    avalanche: '0xC011882d0f7672D8942e7fE2248C174eeD640c8f',
    bsc: '0x16cd38b1B54E7abf307Cb2697E2D9321e843d5AA',
  };

  const local = OFTs[network.name];
  const contractAngleOFT = new Contract(local, LayerZeroBridgeERC20__factory.abi, deployer) as LayerZeroBridgeERC20;

  for (const chain of Object.keys(OFTs)) {
    if (chain !== network.name) {
      console.log(chain);
      const trustedRemote = ethers.utils.solidityPack(['address', 'address'], [OFTs[chain], local]);
      console.log(`Trusted remote ${trustedRemote}`);
      console.log(
        contractAngleOFT.interface.encodeFunctionData('setTrustedRemote', [(LZ_CHAINIDS as any)[chain], trustedRemote]),
      );
      console.log('');
    }
  }
};

func.tags = ['LayerZeroSources'];
export default func;
