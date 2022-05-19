const HDWalletProvider = require('@truffle/hdwallet-provider');
require('dotenv').config();

module.exports = {
  networks: {
    development: {
      host      : '127.0.0.1',
      port      : 8545,
      network_id: '*',
    },
    rinkeby: {
      provider() {
        return new HDWalletProvider(
          'pumpkin pig sword between illness rhythm treat demand anger valid door flat',
          'wss://rinkeby.infura.io/ws/v3/55f261e35c8e4eab884e82e8801bf3af'
        );
      },
      network_id         : 4,
      networkCheckTimeout: 1000000,
      timeoutBlocks      : 200
    },
  },

  mocha: {
    // reporter: 'eth-gas-reporter',
  },

  solc: {
    optimizer: {
      enabled: true,
      runs   : 200,
    },
  },

  compilers: {
    solc: {
      version: '0.8.4',
    },
  },
};
