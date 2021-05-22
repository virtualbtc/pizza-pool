// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./VirtualBitcoinInterface.sol";

contract PizzaPool {

    event CreatePool(address owner, uint256 poolId, uint256 power);
    event ChangePool(address owner, uint256 poolId, uint256 power);
    event DeletePool(address owner, uint256 poolId);
    event JoinPool(address owner, uint256 poolId, uint256 amount);
    event ChangeSlice(address owner, uint256 poolId, uint256 sliceId, uint256 amount);
    event DeleteSlice(uint256 poolId, uint256 sliceId);
    event TakePool(uint256 poolId, uint256 subsidy);
    event Distribute(uint256 poolId, uint256 sliceId, uint256 subsidy);

    VirtualBitcoinInterface private vbtc;
    
    struct Pool {
        uint256 pizzaId;
        address owner;
        
        uint256 inSlice;
        uint256 outSlice;

        uint256 accSubsidyBlock;
        uint256 inAccSubsidy;
        uint256 outAccSubsidy;
        
        uint256 takenBlock;
        uint256 takenAccSubsidy;
    }
    Pool[] public pools;
    mapping(uint256 => uint256) public pizzaToPool;

    struct Slice {
        address owner;
        uint256 amount;
        uint256 minedBlock;
        uint256 accSubsidy;
    }
    mapping(uint256 => Slice[]) public slices;
    mapping(uint256 => mapping(address => uint256)) public ownerToSlice;

    constructor(address vbtcAddress) {
        vbtc = VirtualBitcoinInterface(vbtcAddress);
    }

    function calculateAccSubsidy(uint256 poolId) internal view returns (uint256) {
        Pool memory pool = pools[poolId];
        return pool.inAccSubsidy + pool.outAccSubsidy + vbtc.subsidyOf(pool.pizzaId) / vbtc.powerOf(pool.pizzaId);
    }

    function poolCount() external view returns (uint256) {
        return pools.length;
    }

    function createPool(uint256 power) external returns (uint256) {
        
        uint256 pizzaId = vbtc.buyPizza(power);
        uint256 price = vbtc.pizzaPrice(power);

        vbtc.transferFrom(msg.sender, address(this), price);

        uint256 poolId = pools.length;
        pools.push(Pool({
            owner: msg.sender,
            pizzaId: pizzaId,
            
            inSlice: price,
            outSlice: 0,

            accSubsidyBlock: block.number,
            inAccSubsidy: 0,
            outAccSubsidy: 0,
            
            takenBlock: block.number,
            takenAccSubsidy: 0
        }));

        slices[poolId].push();

        emit CreatePool(msg.sender, poolId, power);

        return poolId;
    }

    function changePool(uint256 poolId, uint256 power) external {

        Pool storage pool = pools[poolId];
        require(pool.owner == msg.sender);
        require(pool.outSlice <= vbtc.pizzaPrice(power));

        uint256 pizzaId = pool.pizzaId;
        uint256 currentPower = vbtc.powerOf(pizzaId);
        require(currentPower != power);
        mine(poolId);

        vbtc.changePizza(pizzaId, power);

        if (currentPower < power) { // upgrade
            uint256 price = vbtc.pizzaPrice(power - currentPower);
            pool.inSlice += price;
            vbtc.transferFrom(msg.sender, address(this), price);
        } else { // downgrade
            uint256 price = vbtc.pizzaPrice(currentPower - power);
            pool.inSlice -= price;
            vbtc.transferFrom(address(this), msg.sender, price);
        }

        emit ChangePool(msg.sender, poolId, power);
    }

    function deletePool(uint256 poolId) external {

        Pool memory pool = pools[poolId];
        require(pool.owner == msg.sender);

        mine(poolId);

        Slice[] memory s = slices[poolId];
        uint256 sl = s.length;

        for (uint256 sliceId = 0; sliceId < sl; sliceId += 1) {
            distribute(pool.accSubsidyBlock, poolId, sliceId);
            Slice memory slice = s[sliceId];
            vbtc.transferFrom(address(this), slice.owner, slice.amount);
        }
        
        delete pools[poolId];
        delete slices[poolId];

        vbtc.transferFrom(address(this), msg.sender, pool.inSlice);

        emit DeletePool(msg.sender, poolId);
    }

    function sliceCount(uint256 poolId) external view returns (uint256) {
        return slices[poolId].length;
    }

    function joinPool(uint256 poolId, uint256 amount) external {
        require(ownerToSlice[poolId][msg.sender] == 0);
        
        Pool storage pool = pools[poolId];
        require(pool.owner != address(0));
        require(pool.inSlice >= amount);

        slices[poolId].push(Slice({
            owner: msg.sender,
            amount: amount,
            minedBlock: block.number,
            accSubsidy: 0
        }));

        mine(poolId);
        pool.inSlice -= amount;
        pool.outSlice += amount;

        vbtc.transferFrom(msg.sender, address(this), amount);

        emit JoinPool(msg.sender, poolId, amount);
    }

    function changeSlice(uint256 poolId, uint256 amount) external {
        
        uint256 sliceId = ownerToSlice[poolId][msg.sender];
        require(sliceId != 0);
        Slice storage slice = slices[poolId][sliceId];
        
        uint256 currentAmount = slice.amount;
        require(currentAmount != amount);
        
        Pool storage pool = pools[poolId];
        distribute(pool.outAccSubsidy, poolId, sliceId);

        slice.amount = amount;

        if (currentAmount < amount) { // upgrade
            uint256 diff = amount - currentAmount;
            pool.inSlice -= diff;
            pool.outSlice += diff;
            vbtc.transferFrom(msg.sender, address(this), diff);
        } else { // downgrade
            uint256 diff = currentAmount - amount;
            pool.inSlice += diff;
            pool.outSlice -= diff;
            vbtc.transferFrom(address(this), msg.sender, diff);
        }
        
        emit ChangeSlice(msg.sender, poolId, sliceId, amount);
    }
    
    function _deleteSlice(uint256 poolId, uint256 sliceId) internal {
        
        Slice memory slice = slices[poolId][sliceId];
        
        address owner = slice.owner;
        uint256 amount = slice.amount;
        
        Pool storage pool = pools[poolId];
        distribute(pool.outAccSubsidy, poolId, sliceId);

        delete slices[poolId][sliceId];
        ownerToSlice[poolId][owner] = 0;

        pool.inSlice += amount;
        pool.outSlice -= amount;
        vbtc.transferFrom(address(this), owner, amount);
        
        emit DeleteSlice(poolId, sliceId);
    }

    function exitPool(uint256 poolId) external {
        uint256 sliceId = ownerToSlice[poolId][msg.sender];
        require(sliceId != 0);
        _deleteSlice(poolId, sliceId);
    }

    function deleteSlice(uint256 poolId, uint256 sliceId) external {
        require(pools[poolId].owner == msg.sender);
        _deleteSlice(poolId, sliceId);
    }

    function subsidyOf(uint256 poolId) external view returns (uint256) {
        Pool memory pool = pools[poolId];
        return (calculateAccSubsidy(poolId) - pool.inAccSubsidy - pool.outAccSubsidy) * (block.number - pool.accSubsidyBlock);
    }
    
    function mine(uint256 poolId) public {
        Pool storage pool = pools[poolId];
        uint256 accSubsidy = (calculateAccSubsidy(poolId) - pool.inAccSubsidy - pool.outAccSubsidy) * (block.number - pool.accSubsidyBlock);
        pool.inAccSubsidy = accSubsidy * (pool.inSlice + pool.outSlice) / pool.inSlice;
        pool.outAccSubsidy = accSubsidy - pool.inAccSubsidy;
        pool.accSubsidyBlock = block.number;
        vbtc.mine(pool.pizzaId);
    }

    function takePool(uint256 poolId) external {
        
        Pool storage pool = pools[poolId];

        uint256 subsidy = (pool.inAccSubsidy - pool.takenAccSubsidy) * (block.number - pool.takenBlock);
        vbtc.transferFrom(address(this), pool.owner, subsidy);

        pool.takenBlock = block.number;
        pool.takenAccSubsidy = pool.inAccSubsidy;

        emit TakePool(poolId, subsidy);
    }

    function distribute(uint256 poolAccSubsidy, uint256 poolId, uint256 sliceId) internal {

        Slice storage slice = slices[poolId][sliceId];

        uint256 subsidy = (poolAccSubsidy - slice.accSubsidy) * (block.number - slice.minedBlock);
        vbtc.transferFrom(address(this), slice.owner, subsidy);

        slice.minedBlock = block.number;
        slice.accSubsidy = poolAccSubsidy;

        emit Distribute(poolId, sliceId, subsidy);
    }

    function takeSlice(uint256 poolId) external {
        uint256 sliceId = ownerToSlice[poolId][msg.sender];
        require(sliceId != 0);
        mine(poolId);
        distribute(pools[poolId].outAccSubsidy, poolId, sliceId);
    }
}