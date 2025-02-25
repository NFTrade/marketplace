const HDWalletProvider = require('@truffle/hdwallet-provider');

require('dotenv').config();

module.exports = {
  networks: {
    development: {
      host      : '127.0.0.1',
      port      : 8545,
      network_id: '*',
    },
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

  plugins: [
    'solidity-coverage'
  ]
};
