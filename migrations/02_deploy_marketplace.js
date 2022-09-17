const ERC20Proxy = artifacts.require('ERC20Proxy');
const ERC721Proxy = artifacts.require('ERC721Proxy');
const ERC1155Proxy = artifacts.require('ERC1155Proxy');
const MultiAssetProxy = artifacts.require('MultiAssetProxy');
const NiftyProtocol = artifacts.require('NiftyProtocol');
const LibAssetData = artifacts.require('LibAssetData');

const chainId = 4;

const deploy = async (deployer, network, accounts) => {
  await deployer.deploy(LibAssetData);

  await deployer.deploy(ERC20Proxy);
  await deployer.deploy(ERC721Proxy);
  await deployer.deploy(ERC1155Proxy);
  await deployer.deploy(MultiAssetProxy);
  await deployer.deploy(NiftyProtocol, chainId);

  console.log('done running migrations');
};

module.exports = deploy;
