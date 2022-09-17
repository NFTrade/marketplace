const NiftyProtocol = artifacts.require('NiftyProtocol');

const FEE_COLLECTOR = '0x1249CAE9fAbbDc18F5368355Ac1FEBD06b426374';
const EXCHANGE = '0x4b75ba193755a52f5b6398466cb3e9458610cbaf';

module.exports = async function (callback) {
  // perform actions
  const exchange = await NiftyProtocol.at(EXCHANGE);

  const executeTransaction = async (action, num) => {
    try {
      console.log(await action(), num);
    } catch (e) {
      console.log(e, num);
    }
  };

  const marketplaceIdentifier = web3.utils.sha3('nftrade');

  await executeTransaction(() => exchange.setProtocolFeeMultiplier('2'), 1);
  await executeTransaction(() => exchange.setProtocolFeeCollectorAddress(FEE_COLLECTOR), 2);
  await executeTransaction(() => exchange.registerMarketplace(marketplaceIdentifier, 0, FEE_COLLECTOR), 3);

  callback();
};
