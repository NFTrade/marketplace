const ERC20Proxy = artifacts.require('ERC20Proxy');
const ERC721Proxy = artifacts.require('ERC721Proxy');
const ERC1155Proxy = artifacts.require('ERC1155Proxy');
const MultiAssetProxy = artifacts.require('MultiAssetProxy');
const NiftyProtocol = artifacts.require('NiftyProtocol');
const LibAssetData = artifacts.require('LibAssetData');

const WETH_ADDRESS = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
const LIBASSET = '0x4FB6f91904D2318274CDB5812480835f6859dFEa';
const EXCHANGE = '0x4b75ba193755a52f5b6398466cb3e9458610cbaf';
const MULTI = '0xf23a1357694A4823FC4C51654692d5f635bb9233';
const ERC1155P = '0xa2f950ccb80909FF80eB6dCd7cD915D85A1f6c25';
const ERC721P = '0x72F864fce4594E98e3378F06FA69D7824a223E44';
const ERC20P = '0x474363A12b5966F7D8221c0a4B0fD31337F7BD83';

module.exports = async function (callback) {
  // perform actions
  const libAssetData = await LibAssetData.at(LIBASSET);
  const erc20Proxy = await ERC20Proxy.at(ERC20P);
  const erc721Proxy = await ERC721Proxy.at(ERC721P);
  const erc1155Proxy = await ERC1155Proxy.at(ERC1155P);
  const multiAssetProxy = await MultiAssetProxy.at(MULTI);
  const exchange = await NiftyProtocol.at(EXCHANGE);

  const executeTransaction = async (action, num) => {
    try {
      console.log(await action(), num);
    } catch (e) {
      console.log(e, num);
    }
  };

  await executeTransaction(() => erc20Proxy.addAuthorizedAddress(exchange.address), 1);
  await executeTransaction(() => erc721Proxy.addAuthorizedAddress(exchange.address), 2);
  await executeTransaction(() => erc1155Proxy.addAuthorizedAddress(exchange.address), 3);
  await executeTransaction(() => multiAssetProxy.addAuthorizedAddress(exchange.address), 4);

  // MultiAssetProxy
  await executeTransaction(() => erc20Proxy.addAuthorizedAddress(multiAssetProxy.address), 5);
  await executeTransaction(() => erc721Proxy.addAuthorizedAddress(multiAssetProxy.address), 6);
  await executeTransaction(() => erc1155Proxy.addAuthorizedAddress(multiAssetProxy.address), 7);

  await executeTransaction(() => multiAssetProxy.registerAssetProxy(erc20Proxy.address), 8);
  await executeTransaction(() => multiAssetProxy.registerAssetProxy(erc721Proxy.address), 9);
  await executeTransaction(() => multiAssetProxy.registerAssetProxy(erc1155Proxy.address), 10);

  await executeTransaction(() => exchange.registerAssetProxy(erc20Proxy.address), 11);
  await executeTransaction(() => exchange.registerAssetProxy(erc721Proxy.address), 12);
  await executeTransaction(() => exchange.registerAssetProxy(erc1155Proxy.address), 13);
  await executeTransaction(() => exchange.registerAssetProxy(multiAssetProxy.address), 14);

  await executeTransaction(() => erc20Proxy.addToken(WETH_ADDRESS), 15);

  callback();
};
