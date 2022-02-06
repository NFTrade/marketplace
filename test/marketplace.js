const ERC20Proxy = artifacts.require('ERC20Proxy');
const ERC721Proxy = artifacts.require('ERC721Proxy');
const ERC71155Proxy = artifacts.require('ERC1155Proxy');
const Exchange = artifacts.require('Exchange');
const LibAssetData = artifacts.require('LibAssetData');
const NFT = artifacts.require('NFT');
const WETH = artifacts.require('WETH');
const BigNumber = require('bignumber.js');

const Provider = require('@truffle/hdwallet-provider');
const { signTyped } = require('./signature');

const chainId = 31337;

const NULL_ADDRESS = '0x0000000000000000000000000000000000000000';
const NULL_BYTES = '0x';
const ZERO = new BigNumber(0).toString();

const tenYearsInSeconds = new BigNumber(Date.now() + 315569520).toString();
const MAX_DIGITS_IN_UNSIGNED_256_INT = 78;

const generatePseudoRandom256BitNumber = () => {
  const randomNumber = BigNumber.random(MAX_DIGITS_IN_UNSIGNED_256_INT);
  const factor = new BigNumber(10).pow(MAX_DIGITS_IN_UNSIGNED_256_INT - 1);
  const randomNumberScaledTo256Bits = randomNumber.times(factor).integerValue();
  return randomNumberScaledTo256Bits;
};

// a little hack
web3.providers.HttpProvider.prototype.sendAsync = web3.providers.HttpProvider.prototype.send;

contract('Exchange', (accounts) => {
  let exchange;
  let libAssetData;
  let erc721proxy;
  let dummyerc721;
  let etherToken;
  let order;
  const provider = web3.currentProvider;

  const owner = accounts[0];
  const buyer = accounts[1];
  const seller = accounts[2];
  before(async () => {
    exchange = await Exchange.deployed();
    libAssetData = await LibAssetData.deployed();

    etherToken = await WETH.deployed();
    erc721proxy = await ERC721Proxy.deployed();

    dummyerc721 = await NFT.new('NFT Test', 'NFTT');

    exchange.setProtocolFeeMultiplier(new BigNumber(0));
    exchange.setNFTradeTradeFee(new BigNumber(150));
    exchange.setNFTradeFeeMultiplier(new BigNumber(150));

    // await token.transfer(user, 1000, { from: owner });
    // reward = await NonTradableERC20.deployed();
  });

  const createNFT = async (from) => {
    // minting a new NFT
    console.log({ async: 'minting a new NFT', from });
    const mintTransaction = await dummyerc721.mint(from, 12341, { from });
    const tokenID = mintTransaction.logs[0].args.tokenId;

    console.log('minted tokenID:', tokenID.toString());

    return tokenID;
  };

  describe('Exchange Flow', () => {
    it('List an asset', async () => {
      const tokenID = await createNFT(seller);

      const makerAssetAmount = new BigNumber(1); // need to populate these

      const price = '0.01';
      const unit = new BigNumber(10).pow(18);
      const baseUnitAmount = unit.times(new BigNumber(price));
      const takerAssetAmount = baseUnitAmount;

      const takerAssetData = await libAssetData.encodeERC20AssetData(etherToken.address);

      const makerAssetData = await libAssetData.encodeERC721AssetData(dummyerc721.address, tokenID);

      const newOrder = {
        chainId,
        exchangeAddress      : exchange.address,
        makerAddress         : seller,
        takerAddress         : NULL_ADDRESS,
        senderAddress        : NULL_ADDRESS,
        feeRecipientAddress  : NULL_ADDRESS,
        expirationTimeSeconds: tenYearsInSeconds.toString(),
        salt                 : generatePseudoRandom256BitNumber().toString(),
        makerAssetAmount     : makerAssetAmount.toString(),
        takerAssetAmount     : takerAssetAmount.toString(),
        makerAssetData,
        takerAssetData,
        makerFeeAssetData    : NULL_BYTES,
        takerFeeAssetData    : NULL_BYTES,
        makerFee             : ZERO.toString(),
        takerFee             : ZERO.toString(),
      };

      let signedOrder;
      try {
        // Generate the order hash and sign it
        signedOrder = await signTyped(
          provider,
          newOrder,
          seller,
          exchange.address
        );
      } catch (e) {
        console.log(e);
      }

      const isApprovedForAll = await dummyerc721
        .isApprovedForAll(seller, erc721proxy.address, { from: seller });

      if (!isApprovedForAll) {
        const ERC721Approval = await dummyerc721
          .setApprovalForAll(erc721proxy.address, true, { from: seller });
        const { transactionHash } = ERC721Approval;
        console.log('approving');
      } else {
        console.log('already approved');
      }
      assert.isTrue(isApprovedForAll, 'ERC721Proxy must be preapproved on our NFT Token');

      const { orderHash } = await exchange.getOrderInfo(signedOrder);

      assert.isNotEmpty(orderHash);

      order = { signedOrder, orderHash };
    });
    it('Buying a listed asset', async () => {
      const averageGas = await web3.eth.getGasPrice();
      const affiliateFeeRecipient = NULL_ADDRESS;
      const affiliateFee = ZERO;

      const takerAssetAmount = new BigNumber(order.signedOrder.takerAssetAmount);

      const buyOrder = await exchange.fillOrder(
        order.signedOrder,
        order.signedOrder.takerAssetAmount,
        order.signedOrder.signature,
        {
          from    : buyer,
          gasPrice: averageGas,
          value   : takerAssetAmount,
        }
      );
    });
  });
});
