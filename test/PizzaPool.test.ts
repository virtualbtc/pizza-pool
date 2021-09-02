import { VirtualBitcoin, PizzaPool } from "../typechain";

import { ethers } from "hardhat";
import { BigNumberish, Wallet } from "ethers";
import { expect } from "chai";
import { mine, autoMining } from "./utils/blocks";

const { constants } = ethers;
const { AddressZero } = constants;

const setupTest = async () => {
  const signers = await ethers.getSigners();
  const [deployer, alice, bob, carol, dan, erin] = signers;

  const VirtualBitcoin = await ethers.getContractFactory("VirtualBitcoin");
  const vbtc = (await VirtualBitcoin.deploy()) as VirtualBitcoin;

  const PizzaPool = await ethers.getContractFactory("PizzaPool");
  const pool = (await PizzaPool.deploy(vbtc.address)) as PizzaPool;

  return {
    deployer,
    alice,
    bob,
    carol,
    dan,
    erin,
    vbtc,
    pool,
  };
};

describe("PizzaPool", () => {
  beforeEach(async () => {
    await ethers.provider.send("hardhat_reset", []);
  });

  it("should be ___", async () => {
    const { alice, bob, carol, dan, erin, vbtc, pool } = await setupTest();
  });
});
