import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "dotenv/config";
import "@typechain/hardhat";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.5",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${process.env.INFURA_API_KEY}`,
      // accounts: [process.env.ADMIN || ''],
      chainId: 4,
    },
    kovan: {
      url: `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`,
      // accounts: [process.env.ADMIN || ''],
      chainId: 42,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
