// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import "./interfaces/IPizzaPool.sol";
import "./interfaces/IVirtualBitcoin.sol";

contract PizzaPool is IPizzaPool {
    
    IVirtualBitcoin private vbtc;
    
    struct Pool {
        uint256 pizzaId;
        address owner;
        uint256 sliceAllowed;
        uint256 sliceAllowedPrice;
        uint256 sliceOwned;
        uint256 currentBalance;
        uint256 sharePerSlice;
        uint256 ownerClaimed;
        uint256 fee;
    }
    Pool[] public pools;
    mapping(uint256 => uint256) public pizzaToPool;
    
    struct Slice {
        address owner;
        address amount;
        uint256 price;
        uint256 claimed;
    }
    mapping(uint256 => Slice[]) public slices;
    mapping(uint256 => mapping(address => uint256)) public ownerToSlice;

    constructor(IVirtualBitcoin _vbtc) {
        vbtc = _vbtc;
    }

    function poolCount() override external view returns (uint256) {
        return pools.length;
    }

    function createPool(uint256 power, uint256 sliceAllowed, uint256 sliceAllowedPrice, uint256 fee) override external returns (uint256) {
        
        uint256 price = vbtc.pizzaPrice(power);
        require(sliceAllowed <= price);
        
        vbtc.transferFrom(msg.sender, address(this), price);

        uint256 pizzaId = vbtc.buyPizza(power);
        uint256 poolId = pools.length;

        pools.push(Pool({
            pizzaId: pizzaId,
            owner: msg.sender,
            sliceAllowed: sliceAllowed,
            sliceAllowedPrice: sliceAllowedPrice,
            sliceOwned: 0,
            currentBalance: 0,
            sharePerSlice: 0,
            ownerClaimed: 0,
            fee: fee
        }));

        pizzaToPool[pizzaId] = poolId;

        slices[poolId].push(); // add empty slice
        emit CreatePool(msg.sender, poolId, power, sliceAllowed, sliceAllowedPrice, fee);
        return poolId;
    }
    
    function updateBalance(Pool storage pool) internal {
        uint256 balance = vbtc.subsidyOf(pool.pizzaId);
        require(balance > 0);
        uint256 value = balance - pool.currentBalance;
        if (value > 0) {
            pool.sharePerSlice += value * 1e8 / vbtc.pizzaPrice(pool.power);
        }
        pool.currentBalance = balance;
    }

    function changePool(uint256 poolId, uint256 power, uint256 sliceAllowed, uint256 sliceAllowedPrice, uint256 fee) override external {
        
        Pool storage pool = pools[poolId];
        
        require(pool.owner == msg.sender);
        require(sliceAllowed <= pool.sliceOwned && sliceAllowed <= vbtc.pizzaPrice(power));
        require(fee <= pool.fee);

        updateBalance(pool);
        pool.sliceAllowed = sliceAllowed;
        pool.sliceAllowedPrice = sliceAllowedPrice;
        pool.fee = fee;
        
        uint256 pizzaId = pool.pizzaId;
        uint256 currentPower = vbtc.powerOf(pizzaId);
        if (currentPower < power) { // upgrade
            uint256 price = vbtc.pizzaPrice(power - currentPower);
            vbtc.transferFrom(msg.sender, address(this), price);
        } else if (currentPower > power) { // downgrade
            uint256 price = vbtc.pizzaPrice(currentPower - power);
            vbtc.transfer(msg.sender, price);
        }
        
        vbtc.changePizza(pizzaId, power);
        emit ChangePool(msg.sender, poolId, power, sliceAllowed, sliceAllowedPrice, fee);
    }

    function deletePool(uint256 poolId) override external {
        Pool memory pool = pools[poolId];
        require(pool.owner == msg.sender);
        require(pool.sliceOwned == 0);
        
        uint256 pizzaId = pool.pizzaId;
        uint256 balance = vbtc.subsidyOf(pizzaId) + vbtc.pizzaPrice(vbtc.powerOf(pizzaId));
        vbtc.sellPizza(pizzaId);
        vbtc.transfer(msg.sender, balance);

        delete pools[poolId];
        delete pizzaToPool[pizzaId];

        emit DeletePool(msg.sender, poolId);
    }
    
    function sliceCount(uint256 poolId) override external view returns (uint256) {
        return slices[poolId].length;
    }

    function joinPool(uint256 poolId, uint256 amount) override external {
        require(ownerToSlice[poolId][msg.sender] == 0);

        Pool storage pool = pools[poolId];
        require(pool.owner != address(0));
        require(pool.sliceAllowed - pool.sliceOwned >= amount);

        uint256 price = amount * pool.sliceAllowedPrice / pool.sliceAllowed;

        Slice[] storage ss = slices[poolId];
        uint256 sliceId = ss.length;
        ss.push(Slice({
            owner: msg.sender,
            amount: amount,
            price: price,
            claimed: 0
        }));
        
        pool.sliceOwned += amount;
        ownerToSlice[poolId][msg.sender] = sliceId;

        vbtc.transferFrom(msg.sender, pool.owner, price);
        emit JoinPool(msg.sender, poolId, amount);
    }

    function changeSlice(uint256 poolId, uint256 amount) override external {
        
        uint256 sliceId = ownerToSlice[poolId][msg.sender];
        require(sliceId != 0);
        Slice storage slice = slices[poolId][sliceId];
        
        uint256 currentAmount = slice.amount;
        require(currentAmount != amount);

        claimSlice(poolId);

        Pool storage pool = pools[poolId];
        if (currentAmount < amount) { // upgrade
            uint256 diff = amount - currentAmount;
            pool.sliceOwned += diff;
            uint256 price = diff * pool.sliceAllowedPrice / pool.sliceAllowed;
            vbtc.transferFrom(msg.sender, pool.owner, price);
        }
    }

    function exitPool(uint256 poolId) override external {

    }
    
    function subsidyPoolOf(uint256 poolId) override external view returns (uint256) {

    }

    function claimPool(uint256 poolId) override external {

    }

    function subsidySliceOf(uint256 poolId) override external view returns (uint256) {

    }

    function claimSlice(uint256 poolId) public external {
        
    }
}
