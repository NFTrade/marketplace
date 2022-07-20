/* eslint-disable no-restricted-syntax */
const {
  fromRpcSig, bufferToHex, toBuffer, keccak256,
} = require('ethereumjs-util');

const BigNumber = require('bignumber.js');

const ethers = require('ethers');

const EIP712Domain = [
  {
    name: 'name',
    type: 'string',
  },
  {
    name: 'version',
    type: 'string',
  },
  {
    name: 'chainId',
    type: 'uint256',
  },
  {
    name: 'verifyingContract',
    type: 'address',
  },
];

const Order = [
  {
    name: 'makerAddress',
    type: 'address',
  },
  {
    name: 'takerAddress',
    type: 'address',
  },
  {
    name: 'royaltiesAddress',
    type: 'address',
  },
  {
    name: 'senderAddress',
    type: 'address',
  },
  {
    name: 'makerAssetAmount',
    type: 'uint256',
  },
  {
    name: 'takerAssetAmount',
    type: 'uint256',
  },
  {
    name: 'royaltiesAmount',
    type: 'uint256',
  },
  {
    name: 'expirationTimeSeconds',
    type: 'uint256',
  },
  {
    name: 'salt',
    type: 'uint256',
  },
  {
    name: 'makerAssetData',
    type: 'bytes',
  },
  {
    name: 'takerAssetData',
    type: 'bytes',
  },
];

/**
 *   @signTypedDataUtils - utils for signature hexing/hashing/encoding
 */
const signTypedDataUtils = {

  findDependencies(primaryType, types, found = []) {
    if (found.includes(primaryType) || types[primaryType] === undefined) {
      return found;
    }
    found.push(primaryType);
    for (const field of types[primaryType]) {
      for (const dep of signTypedDataUtils.findDependencies(field.type, types, found)) {
        if (!found.includes(dep)) {
          found.push(dep);
        }
      }
    }
    return found;
  },
  encodeType(primaryType, types) {
    let deps = signTypedDataUtils.findDependencies(primaryType, types);
    deps = deps.filter((d) => d !== primaryType);
    deps = [primaryType].concat(deps.sort());
    let result = '';
    for (const dep of deps) {
      result += `${dep}(${types[dep].map(({ name, type }) => `${type} ${name}`).join(',')})`;
    }
    return result;
  },
  encodeData(primaryType, data, types) {
    const encodedTypes = ['bytes32'];
    const encodedValues = [signTypedDataUtils.typeHash(primaryType, types)];
    for (const field of types[primaryType]) {
      const value = data[field.name];
      if (field.type === 'string') {
        const hashValue = keccak256(Buffer.from(value));
        encodedTypes.push('bytes32');
        encodedValues.push(hashValue);
      } else if (field.type === 'bytes') {
        const hashValue = keccak256(toBuffer(value));
        encodedTypes.push('bytes32');
        encodedValues.push(hashValue);
      } else if (types[field.type] !== undefined) {
        encodedTypes.push('bytes32');
        const hashValue = keccak256(
          // tslint:disable-next-line:no-unnecessary-type-assertion
          toBuffer(signTypedDataUtils.encodeData(field.type, value, types)),
        );
        encodedValues.push(hashValue);
      } else if (field.type.lastIndexOf(']') === field.type.length - 1) {
        throw new Error('Arrays currently unimplemented in encodeData');
      } else {
        encodedTypes.push(field.type);
        const normalizedValue = signTypedDataUtils.normalizeValue(field.type, value);
        encodedValues.push(normalizedValue);
      }
    }
    return ethers.utils.defaultAbiCoder.encode(encodedTypes, encodedValues);
  },
  normalizeValue(type, value) {
    const STRING_BASE = 10;
    if (type === 'uint256') {
      if (BigNumber.isBigNumber(value)) {
        return value.toString(STRING_BASE);
      }
      return new BigNumber(value).toString(STRING_BASE);
    }
    return value;
  },
  typeHash(primaryType, types) {
    return keccak256(Buffer.from(signTypedDataUtils.encodeType(primaryType, types)));
  },
  structHash(primaryType, data, types) {
    return keccak256(toBuffer(signTypedDataUtils.encodeData(primaryType, data, types)));
  },
  parseSignatureHexAsRSV(signatureHex) {
    const { v, r, s } = fromRpcSig(signatureHex);
    const ecSignature = {
      v,
      r: bufferToHex(r),
      s: bufferToHex(s),
    };
    return ecSignature;
  },
  /**
* Convert a string, a number, a Buffer, or a BigNumber into a hex string.
* Works with negative numbers, as well.
*/
  toHex(n) {
    return `0x${n.toString('hex')}`;
  },
  /**
 * Get the keccak hash of some data.
 */
  hash(typedData) {
    const n = keccak256(Buffer.concat([
      Buffer.from('1901', 'hex'),
      signTypedDataUtils.structHash('EIP712Domain', typedData.domain, typedData.types),
      signTypedDataUtils.structHash(typedData.primaryType, typedData.message, typedData.types),
    ]));
    return this.toHex(n);
  },
};
/**
 *   @send - send message to and open metamask
 */
const send = (provider, data) => new Promise((resolve, reject) => provider.sendAsync(data, (err, result) => {
  if (result.error) {
    err = result.error;
  }
  if (err) {
    console.log(err, result);
    return reject(err);
  }
  console.log(result);
  return resolve(result.result);
}));
/**
 *   @signTypedData - function that handles signing and metamask interaction
 */
const signTypedData = async (provider, address, payload) => {
  // console.log(provider);
  const methodsToTry = ['eth_signTypedData_v4', 'eth_signTypedData_v3', 'eth_signTypedData'];

  let lastErr;
  // eslint-disable-next-line no-restricted-syntax
  for await (const method of methodsToTry) {
    const typedData = {
      id    : method.indexOf(),
      params: [
        address,
        method === 'eth_signTypedData' ? payload : JSON.stringify(payload),
      ],
      jsonrpc: '2.0',
      method,
    };

    try {
      const response = await send(provider, typedData);
      console.log(method, response);
      return response;
    } catch (err) {
      lastErr = err;
      console.error('err', err);
      // If there are no more methods to try or the error says something other
      // than the method not existing, throw.
      /* if (!/(not handled|does not exist|not supported)/.test(err.message)) {
        throw err;
      } */
    }
  }

  throw lastErr;
};

const signEth = async (provider, address, payload) => {
  const orderHash = signTypedDataUtils.hash(payload);
  return send(provider, {
    method: 'eth_sign',
    params: [address, orderHash],
  });
};

/**
 *   @signTyped - main function to be called when signing
 */
module.exports = async (provider, order, from, verifyingContract) => {
  const typedData = {
    types: {
      EIP712Domain,
      Order,
    },
    domain: {
      name   : 'Nifty Exchange',
      version: '2.0',
      chainId: order.chainId,
      verifyingContract,
    },
    message    : order,
    primaryType: 'Order',
  };

  let signature;
  try {
    /* if (!window.ethereum || !window.ethereum.isMetaMask) {
      // if not using metamask use signEth
      throw new Error('using eth_sign');
    } */
    signature = await signTypedData(provider, from, typedData);
    console.log('here', signature);
  } catch (err) {
    console.log(err);
    // HACK: We are unable to handle specific errors thrown since provider is not an object
    //       under our control. It could be Metamask Web3, Ethers, or any general RPC provider.
    //       We check for a user denying the signature request in a way that supports Metamask and
    //       Coinbase Wallet. Unfortunately for signers with a different error message,
    //       they will receive two signature requests.
    if (err.message.includes('User denied message signature')) {
      throw err;
    }
    signature = await signEth(provider, from, typedData);
  }
  if (!signature) {
    throw new Error('No Signature');
  }

  const ecSignatureRSV = signTypedDataUtils.parseSignatureHexAsRSV(signature);
  const signatureBuffer = Buffer.concat([
    toBuffer(ecSignatureRSV.v),
    toBuffer(ecSignatureRSV.r),
    toBuffer(ecSignatureRSV.s),
    toBuffer(2),
  ]);
  const signatureHex = `0x${signatureBuffer.toString('hex')}`;

  return { ...order, signature: signatureHex };
};
