import { MockVirtualBitcoin, PizzaPool } from "../typechain";

import { ethers } from "hardhat";
import { BigNumberish, Wallet } from "ethers";
import { expect } from "chai";
import { mine, autoMining, mineTo } from "./utils/blocks";

const { constants } = ethers;
const { AddressZero, MaxUint256 } = constants;

const setupTest = async () => {
  const signers = await ethers.getSigners();
  const [deployer, alice, bob, carol, dan, erin] = signers;

  const MockVirtualBitcoin = await ethers.getContractFactory(
    "MockVirtualBitcoin"
  );
  const vbtc = (await MockVirtualBitcoin.deploy()) as MockVirtualBitcoin;

  const PizzaPool = await ethers.getContractFactory("PizzaPool");
  const pool = (await PizzaPool.deploy(vbtc.address)) as PizzaPool;

  for (let i = 0; i < 6; i++) {
    await vbtc.connect(signers[i]).approve(pool.address, MaxUint256);
  }

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

  it("should be that testing basic functions works well", async () => {
    const { deployer, alice, bob, vbtc, pool } = await setupTest();

    const slicesPerPower = await pool.SLICES_PER_POWER();

    await mineTo(100);
    await expect(pool.createPool(1)).to.emit(pool, "CreatePool").withArgs(0, deployer.address, 1, 1);
    const pool0 = await pool.pools(0);
    expect(await pool.pizzaToPool(pool0.pizzaId)).to.be.equal(0);
    expect(await pool.slices(0, deployer.address)).to.be.equal(
      slicesPerPower.mul(1)
    );

    await expect(pool.changePool(0, 1)).to.be.reverted;
    await expect(pool.connect(alice).changePool(0, 2)).to.be.reverted;

    await mineTo(110);
    let reward = (await vbtc.subsidyAt(110)).mul(10).div(2);
    await expect(() => pool.changePool(0, 9)).to.changeTokenBalance(
      vbtc,
      deployer,
      slicesPerPower.mul(-8)
    );

    reward = reward.add((await vbtc.subsidyAt(111)).mul(9).div(10));
    await expect(() => pool.changePool(0, 4)).to.changeTokenBalance(
      vbtc,
      deployer,
      slicesPerPower.mul(5)
    );
    
    await expect(pool.connect(alice).deletePool(0)).to.be.reverted;
    await expect(pool.deletePool(1)).to.be.reverted;

    await mineTo(120);
    reward = reward.add((await vbtc.subsidyAt(120)).mul(9).mul(4).div(5));
    await expect(() => pool.deletePool(0)).to.changeTokenBalance(
      vbtc,
      deployer,
      slicesPerPower.mul(4).add(reward)
    );

    await mineTo(130);
    await expect(pool.createPool(9)).to.emit(pool, "CreatePool").withArgs(1, deployer.address, 2, 9);
    const pool1 = await pool.pools(1);
    expect(await pool.pizzaToPool(pool1.pizzaId)).to.be.equal(1);
    expect(await pool.slices(1, deployer.address)).to.be.equal(
      slicesPerPower.mul(9)
    );

    await expect(pool.sell(1, slicesPerPower.mul(9).add(1), 10000)).to.be.reverted;
    await expect(pool.sell(1, slicesPerPower, 10000)).to.emit(pool, "Sell").withArgs(0, deployer.address, 1, slicesPerPower, 10000);
    await expect(pool.connect(alice).cancelSale(0)).to.be.reverted;
    await expect(pool.cancelSale(0)).to.emit(pool, "CancelSale").withArgs(0);
    
    await mineTo(140);
    await expect(pool.sell(1, slicesPerPower, 10000)).to.emit(pool, "Sell").withArgs(1, deployer.address, 1, slicesPerPower, 10000);
    
    await vbtc.transfer(bob.address, 100000);

    await mineTo(145);
    let rewardD = (await vbtc.subsidyAt(145)).mul(15).mul(9).div(10);
    await expect(() => pool.connect(bob).buy(1, slicesPerPower.div(2))).to.changeTokenBalance(vbtc, bob, -5000);

    expect(await pool.slices(1, deployer.address)).to.be.equal(slicesPerPower.mul(9).sub(slicesPerPower.div(2)));
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower.div(2));
    expect((await pool.sales(1))[2]).to.be.equal(slicesPerPower.div(2));
    expect((await pool.sales(1))[3]).to.be.equal(5000);
    
    rewardD = rewardD.add((await vbtc.subsidyAt(145)).mul(9).div(10).mul(17).div(18));
    await expect(() => pool.connect(bob).buy(1, slicesPerPower.div(4))).to.changeTokenBalance(vbtc, bob, -2500);

    expect(await pool.slices(1, deployer.address)).to.be.equal(slicesPerPower.mul(9).sub(slicesPerPower.div(2)).sub(slicesPerPower.div(4)));
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower.div(2).add(slicesPerPower.div(4)));
    expect((await pool.sales(1))[2]).to.be.equal(slicesPerPower.div(4));
    expect((await pool.sales(1))[3]).to.be.equal(2500);

    await mineTo(160);
    rewardD = rewardD.add((await vbtc.subsidyAt(145)).mul(14).mul(9).div(10).mul(33).div(36));
    await expect(() => pool.mine(1, MaxUint256)).to.changeTokenBalance(vbtc, deployer, rewardD);

    await expect(pool.connect(bob).buy(1, slicesPerPower.div(4))).to.emit(pool, "RemoveSale").withArgs(1);

    expect(await pool.slices(1, deployer.address)).to.be.equal(slicesPerPower.mul(8));
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower);
    expect((await pool.sales(1))[2]).to.be.equal(0);
    expect((await pool.sales(1))[3]).to.be.equal(0);

    await mineTo(170);
    await pool.mine(1, MaxUint256);
    await expect(pool.sell(1, slicesPerPower.mul(8), 20000)).to.emit(pool, "Sell").withArgs(2, deployer.address, 1, slicesPerPower.mul(8), 20000);

    await mineTo(180);
    rewardD = (await vbtc.subsidyAt(145)).mul(10).mul(9).div(10).mul(8).div(9);
    await expect(pool.connect(bob).buy(2, slicesPerPower.mul(8))).to.emit(pool, "RemoveSale").withArgs(2);

    expect(await pool.slices(1, deployer.address)).to.be.equal(0);
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower.mul(9));
    expect((await pool.sales(2))[2]).to.be.equal(0);
    expect((await pool.sales(2))[3]).to.be.equal(0);

    await mineTo(200);
    await expect(() => pool.mine(1, MaxUint256)).to.changeTokenBalance(vbtc, deployer, rewardD);
    await pool.connect(bob).mine(1, MaxUint256);

    await mineTo(210);
    await expect(() => pool.mine(1, MaxUint256)).to.changeTokenBalance(vbtc, deployer, 0);
    
    let rewardB = (await vbtc.subsidyAt(210)).mul(10).mul(9).div(10);
    await expect(() => pool.connect(bob).mine(1, MaxUint256)).to.changeTokenBalance(vbtc, bob, rewardB);
    
  });

  it("should be that testing groupbuying functions works well", async () => {
    const { deployer, alice, bob, erin, vbtc, pool } = await setupTest();

    const slicesPerPower = await pool.SLICES_PER_POWER();

    await mineTo(100);
    await expect(pool.createPool(1)).to.emit(pool, "CreatePool").withArgs(0, deployer.address, 1, 1);
    const pool0 = await pool.pools(0);
    expect(await pool.pizzaToPool(pool0.pizzaId)).to.be.equal(0);
    expect(await pool.slices(0, deployer.address)).to.be.equal(
      slicesPerPower.mul(1)
    );

    await expect(pool.changePool(0, 1)).to.be.reverted;
    await expect(pool.connect(alice).changePool(0, 2)).to.be.reverted;

    await mineTo(110);
    let reward = (await vbtc.subsidyAt(110)).mul(10).div(2);
    await expect(() => pool.changePool(0, 9)).to.changeTokenBalance(
      vbtc,
      deployer,
      slicesPerPower.mul(-8)
    );

    reward = reward.add((await vbtc.subsidyAt(111)).mul(9).div(10));
    await expect(() => pool.changePool(0, 4)).to.changeTokenBalance(
      vbtc,
      deployer,
      slicesPerPower.mul(5)
    );
    
    await expect(pool.connect(alice).deletePool(0)).to.be.reverted;
    await expect(pool.deletePool(1)).to.be.reverted;

    await mineTo(120);
    reward = reward.add((await vbtc.subsidyAt(120)).mul(9).mul(4).div(5));
    await expect(() => pool.deletePool(0)).to.changeTokenBalance(
      vbtc,
      deployer,
      slicesPerPower.mul(4).add(reward)
    );

    await mineTo(130);
    await expect(pool.createPool(9)).to.emit(pool, "CreatePool").withArgs(1, deployer.address, 2, 9);
    const pool1 = await pool.pools(1);
    expect(await pool.pizzaToPool(pool1.pizzaId)).to.be.equal(1);
    expect(await pool.slices(1, deployer.address)).to.be.equal(
      slicesPerPower.mul(9)
    );

    await expect(pool.sell(1, slicesPerPower.mul(9).add(1), 10000)).to.be.reverted;
    await expect(pool.sell(1, slicesPerPower, 10000)).to.emit(pool, "Sell").withArgs(0, deployer.address, 1, slicesPerPower, 10000);
    await expect(pool.connect(alice).cancelSale(0)).to.be.reverted;
    await expect(pool.cancelSale(0)).to.emit(pool, "CancelSale").withArgs(0);
    
    await mineTo(140);
    await expect(pool.sell(1, slicesPerPower, 10000)).to.emit(pool, "Sell").withArgs(1, deployer.address, 1, slicesPerPower, 10000);
    
    await vbtc.transfer(bob.address, 100000);

    await mineTo(145);
    let rewardD = (await vbtc.subsidyAt(145)).mul(15).mul(9).div(10);
    await expect(() => pool.connect(bob).buy(1, slicesPerPower.div(2))).to.changeTokenBalance(vbtc, bob, -5000);

    expect(await pool.slices(1, deployer.address)).to.be.equal(slicesPerPower.mul(9).sub(slicesPerPower.div(2)));
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower.div(2));
    expect((await pool.sales(1))[2]).to.be.equal(slicesPerPower.div(2));
    expect((await pool.sales(1))[3]).to.be.equal(5000);
    
    rewardD = rewardD.add((await vbtc.subsidyAt(145)).mul(9).div(10).mul(17).div(18));
    await expect(() => pool.connect(bob).buy(1, slicesPerPower.div(4))).to.changeTokenBalance(vbtc, bob, -2500);

    expect(await pool.slices(1, deployer.address)).to.be.equal(slicesPerPower.mul(9).sub(slicesPerPower.div(2)).sub(slicesPerPower.div(4)));
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower.div(2).add(slicesPerPower.div(4)));
    expect((await pool.sales(1))[2]).to.be.equal(slicesPerPower.div(4));
    expect((await pool.sales(1))[3]).to.be.equal(2500);

    await mineTo(160);
    rewardD = rewardD.add((await vbtc.subsidyAt(145)).mul(14).mul(9).div(10).mul(33).div(36));
    await expect(() => pool.mine(1, MaxUint256)).to.changeTokenBalance(vbtc, deployer, rewardD);

    await expect(pool.connect(bob).buy(1, slicesPerPower.div(4))).to.emit(pool, "RemoveSale").withArgs(1);

    expect(await pool.slices(1, deployer.address)).to.be.equal(slicesPerPower.mul(8));
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower);
    expect((await pool.sales(1))[2]).to.be.equal(0);
    expect((await pool.sales(1))[3]).to.be.equal(0);

    await mineTo(170);
    await pool.mine(1, MaxUint256);
    await expect(pool.sell(1, slicesPerPower.mul(8), 20000)).to.emit(pool, "Sell").withArgs(2, deployer.address, 1, slicesPerPower.mul(8), 20000);

    await mineTo(180);
    rewardD = (await vbtc.subsidyAt(145)).mul(10).mul(9).div(10).mul(8).div(9);
    await expect(pool.connect(bob).buy(2, slicesPerPower.mul(8))).to.emit(pool, "RemoveSale").withArgs(2);

    expect(await pool.slices(1, deployer.address)).to.be.equal(0);
    expect(await pool.slices(1, bob.address)).to.be.equal(slicesPerPower.mul(9));
    expect((await pool.sales(2))[2]).to.be.equal(0);
    expect((await pool.sales(2))[3]).to.be.equal(0);

    await mineTo(200);
    await expect(() => pool.mine(1, MaxUint256)).to.changeTokenBalance(vbtc, deployer, rewardD);
    await pool.connect(bob).mine(1, MaxUint256);

    await mineTo(210);
    await expect(() => pool.mine(1, MaxUint256)).to.changeTokenBalance(vbtc, deployer, 0);
    
    let rewardB = (await vbtc.subsidyAt(210)).mul(10).mul(9).div(10);
    await expect(() => pool.connect(bob).mine(1, MaxUint256)).to.changeTokenBalance(vbtc, bob, rewardB);
    
  });
});
