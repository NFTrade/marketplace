const ERC20Proxy = artifacts.require('ERC20Proxy');
const ERC721Proxy = artifacts.require('ERC721Proxy');
const ERC1155Proxy = artifacts.require('ERC1155Proxy');
const MultiAssetProxy = artifacts.require('MultiAssetProxy');
const Exchange = artifacts.require('Exchange');
const LibAssetData = artifacts.require('LibAssetData');
const Forwarder = artifacts.require('Forwarder');
const WETH = artifacts.require('WETH');
const NFT = artifacts.require('NFT');
const BigNumber = require('bignumber.js');

const deploy = async (deployer, network, accounts) => {
  // Chain ID
  const chainId = 5777;
  // Ether token
  await deployer.deploy(WETH);

  const etherToken = await WETH.deployed();

  await deployer.deploy(LibAssetData);

  await deployer.link(LibAssetData, ERC1155Proxy);

  await deployer.deploy(ERC20Proxy);
  await deployer.deploy(ERC721Proxy);
  await deployer.deploy(ERC1155Proxy);
  await deployer.deploy(MultiAssetProxy);
  await deployer.deploy(Exchange, chainId);

  const erc20Proxy = await ERC20Proxy.deployed();
  const erc721Proxy = await ERC721Proxy.deployed();
  const erc1155Proxy = await ERC1155Proxy.deployed();
  const multiAssetProxy = await MultiAssetProxy.deployed();
  const exchange = await Exchange.deployed();

  await deployer.deploy(NFT, 'NFT Test', 'NFTT');

  const nft = NFT.deployed();

  await erc20Proxy.addAuthorizedAddress(exchange.address);
  await erc721Proxy.addAuthorizedAddress(exchange.address);
  await erc1155Proxy.addAuthorizedAddress(exchange.address);
  await multiAssetProxy.addAuthorizedAddress(exchange.address);

  // MultiAssetProxy
  await erc20Proxy.addAuthorizedAddress(multiAssetProxy.address);
  await erc721Proxy.addAuthorizedAddress(multiAssetProxy.address);
  await erc1155Proxy.addAuthorizedAddress(multiAssetProxy.address);

  await multiAssetProxy.registerAssetProxy(erc20Proxy.address);
  await multiAssetProxy.registerAssetProxy(erc721Proxy.address);
  await multiAssetProxy.registerAssetProxy(erc1155Proxy.address);

  await exchange.registerAssetProxy(erc20Proxy.address);
  await exchange.registerAssetProxy(erc721Proxy.address);
  await exchange.registerAssetProxy(erc1155Proxy.address);

  await erc20Proxy.addToken(etherToken.address);

  await deployer.deploy(Forwarder, exchange.address, etherToken.address);

  /* await exchange.setProtocolFeeMultiplier(new BigNumber(0));
  await exchange.setNFTradeTradeFee(new BigNumber(0));
  await exchange.setNFTradeFeeMultiplier(new BigNumber(0)); */

  console.log('done running migrations');
};

module.exports = deploy;
