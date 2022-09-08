module.exports = {
    client: require('ganache-cli'),
    providerOptions: {
        host: "localhost",
        port: 8545,
        network_id: "1",
        networkCheckTimeout: 60000,
        fork: "https://rpc.ankr.com/eth",
    }
};