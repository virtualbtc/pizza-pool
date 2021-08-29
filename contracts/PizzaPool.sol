// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import "./interfaces/IPizzaPool.sol";
import "./interfaces/IVirtualBitcoin.sol";

contract PizzaPool is IPizzaPool {
    IVirtualBitcoin private vbtc;

    struct Pool {
        address owner;
        uint256 pizzaId;
        uint256 currentBalance;
        uint256 pointsPerShare;
        uint256 lastRewardBlock;
    }
    Pool[] public override pools;
    mapping(uint256 => uint256) public pizzaToPool;
    mapping(uint256 => mapping(address => uint256)) public slices;
    mapping(uint256 => mapping(address => int256)) internal pointsCorrection;
    mapping(uint256 => mapping(address => uint256)) internal claimed;

    struct Sale {
        address seller;
        uint256 poolId;
        uint256 slice;
        uint256 price;
    }
    Sale[] public override sales;

    uint256 immutable SLICES_PER_POWER;

    constructor(IVirtualBitcoin _vbtc) {
        vbtc = _vbtc;
        SLICES_PER_POWER = _vbtc.pizzaPrice(1);
    }

    function poolCount() external view override returns (uint256) {
        return pools.length;
    }

    function createPool(uint256 power) external override returns (uint256) {
        uint256 slice = SLICES_PER_POWER * power;
        vbtc.transferFrom(msg.sender, address(this), slice);

        uint256 pizzaId = vbtc.buyPizza(power);
        uint256 poolId = pools.length;

        pools.push(
            Pool({
                owner: msg.sender,
                pizzaId: pizzaId,
                currentBalance: 0,
                pointsPerShare: 0,
                lastRewardBlock: block.number
            })
        );

        pizzaToPool[pizzaId] = poolId;

        slices[poolId][msg.sender] = slice;
        emit CreatePool(poolId, msg.sender, pizzaId, power);
        return poolId;
    }

    function updateBalance(
        Pool storage pool,
        uint256 slicesIn,
        uint256 totalSlices
    ) internal {
        pool.lastRewardBlock = block.number;
        pool.pointsPerShare += (slicesIn * 1e60) / totalSlices;
        pool.currentBalance += slicesIn;
    }

    function changePool(uint256 poolId, uint256 power) external override {
        Pool storage pool = pools[poolId];
        require(pool.owner == msg.sender);

        uint256 pizzaId = pool.pizzaId;
        uint256 currentPower = vbtc.powerOf(pizzaId);
        require(currentPower != power);

        bool _update = (block.number != pool.lastRewardBlock);
        if (currentPower < power) {
            // upgrade
            uint256 slice = SLICES_PER_POWER * (power - currentPower);
            slices[poolId][msg.sender] += slice;

            uint256 balanceBefore;
            if (_update) balanceBefore = vbtc.balanceOf(address(this));
            vbtc.transferFrom(msg.sender, address(this), slice);
            vbtc.changePizza(pizzaId, power);
            if (_update) {
                uint256 balanceAfter = vbtc.balanceOf(address(this));
                uint256 slicesIn = balanceAfter - balanceBefore;
                if (slicesIn > 0) updateBalance(pool, slicesIn, SLICES_PER_POWER * currentPower);
            }

            pointsCorrection[poolId][msg.sender] -= int256(pool.pointsPerShare * slice);

            emit ChangePool(poolId, power);
        } else if (currentPower > power) {
            // downgrade
            uint256 slice = SLICES_PER_POWER * (currentPower - power);
            slices[poolId][msg.sender] -= slice;

            uint256 balanceBefore;
            if (_update) balanceBefore = vbtc.balanceOf(address(this));
            vbtc.changePizza(pizzaId, power);
            vbtc.transfer(msg.sender, slice);
            if (_update) {
                uint256 balanceAfter = vbtc.balanceOf(address(this));
                uint256 slicesIn = balanceAfter - balanceBefore;
                if (slicesIn > 0) updateBalance(pool, slicesIn, SLICES_PER_POWER * currentPower);
            }

            pointsCorrection[poolId][msg.sender] += int256(pool.pointsPerShare * slice);

            emit ChangePool(poolId, power);
        }
    }

    function deletePool(uint256 poolId) external override {
        Pool storage pool = pools[poolId];
        require(pool.owner == msg.sender);

        uint256 pizzaId = pool.pizzaId;
        uint256 slice = SLICES_PER_POWER * (vbtc.powerOf(pizzaId));
        slices[poolId][msg.sender] -= slice;

        uint256 balanceBefore = vbtc.balanceOf(address(this));
        vbtc.sellPizza(pizzaId);
        uint256 balanceAfter = vbtc.balanceOf(address(this));

        vbtc.transfer(msg.sender, balanceAfter - balanceBefore);

        delete pools[poolId];
        delete pizzaToPool[pizzaId];
        delete slices[poolId][msg.sender];
        delete pointsCorrection[poolId][msg.sender];
        delete claimed[poolId][msg.sender];

        emit DeletePool(poolId);
    }

    function saleCount() external view override returns (uint256) {
        return sales.length;
    }

    function sell(
        uint256 poolId,
        uint256 slice,
        uint256 price
    ) external override returns (uint256) {
        uint256 saleId = sales.length;
        sales.push(Sale({seller: msg.sender, poolId: poolId, slice: slice, price: price}));

        emit Sell(saleId, msg.sender, poolId, slice, price);
        return saleId;
    }

    function removeSale(uint256 saleId) internal {
        delete sales[saleId];
        emit RemoveSale(saleId);
    }

    function buy(uint256 saleId, uint256 slice) external override {
        Sale storage sale = sales[saleId];
        uint256 poolId = sale.poolId;
        uint256 price = (slice * sale.price) / sale.slice;
        sale.slice -= slice;
        sale.price -= price;

        Pool storage pool = pools[poolId];
        int256 correction = int256(pool.pointsPerShare * slice);
        pointsCorrection[poolId][sale.seller] += correction;
        pointsCorrection[poolId][msg.sender] -= correction;

        slices[poolId][sale.seller] -= slice;
        slices[poolId][msg.sender] += slice;

        vbtc.transferFrom(msg.sender, sale.seller, price);

        emit Buy(saleId, msg.sender, slice);
        if (sale.slice == 0) {
            removeSale(saleId);
        }
    }

    function cancelSale(uint256 saleId) external override {
        Sale memory sale = sales[saleId];
        require(sale.seller == msg.sender);

        emit CancelSale(saleId);
        removeSale(saleId);
    }

    function subsidyOf(uint256 poolId) external view override returns (uint256) {
        Pool memory pool = pools[poolId];
        uint256 pointsPerShare = pool.pointsPerShare;
        uint256 value = vbtc.subsidyOf(pool.pizzaId);
        if (value > 0) {
            pointsPerShare += (value * 1e60) / (SLICES_PER_POWER * vbtc.powerOf(pool.pizzaId));
        }
        return
            uint256(int256(pointsPerShare * slices[poolId][msg.sender]) + pointsCorrection[poolId][msg.sender]) /
            1e60 -
            claimed[poolId][msg.sender];
    }

    function mine(uint256 poolId) external override returns (uint256) {
        Pool storage pool = pools[poolId];
        require(pool.lastRewardBlock != block.number, "Already mined in this block");
        uint256 slicesIn = vbtc.mine(pool.pizzaId);
        if (slicesIn > 0) updateBalance(pool, slicesIn, (SLICES_PER_POWER * vbtc.powerOf(pool.pizzaId)));
        uint256 subsidy = uint256(
            int256(pool.pointsPerShare * slices[poolId][msg.sender]) + pointsCorrection[poolId][msg.sender]
        ) /
            1e60 -
            claimed[poolId][msg.sender];
        if (subsidy > 0) {
            claimed[poolId][msg.sender] += subsidy;
            emit Mine(msg.sender, poolId, subsidy);
            vbtc.transfer(msg.sender, subsidy);
            pool.currentBalance -= subsidy;
        }
        return subsidy;
    }
}
