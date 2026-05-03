// CipherGuard Template — hardhat.config.ts
// Copy this exactly into your FHEVM project root
// Tested and verified working with @fhevm/solidity v0.11+

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import "dotenv/config";

const PRIVATE_KEY  = process.env.PRIVATE_KEY  || "";
const INFURA_KEY   = process.env.INFURA_API_KEY || "";
const ETHERSCAN_KEY = process.env.ETHERSCAN_API_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "cancun", // required for FHEVM
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_KEY}`,
      chainId: 11155111,
      accounts: PRIVATE_KEY ? [`${PRIVATE_KEY}`] : [],
      gasMultiplier: 1.2,
    },
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_KEY,
    },
  },
  paths: {
    sources:   "./contracts",
    tests:     "./test",
    cache:     "./cache",
    artifacts: "./artifacts",
  },
};

export default config;