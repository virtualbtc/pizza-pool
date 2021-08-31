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

    struct GroupBuying {
        uint256 poolId;
        uint256 targetPower;
        uint256 slicesLeft;
    }
    GroupBuying[] public override groupBuyings;
    mapping(uint256 => mapping(address => uint256)) public override groupBuyingSlices;

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
        uint256 _priceLeft = sale.price;
        uint256 _slicesLeft = sale.slice;
        uint256 price = (slice * _priceLeft) / _slicesLeft;

        sale.slice = _slicesLeft - slice;
        sale.price = _priceLeft - price;

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
        Sale storage sale = sales[saleId];
        require(sale.seller == msg.sender);

        emit CancelSale(saleId);
        removeSale(saleId);
    }

    function subsidyOf(uint256 poolId) external view override returns (uint256) {
        Pool storage pool = pools[poolId];
        uint256 pointsPerShare = pool.pointsPerShare;
        uint256 _pizzaId = pool.pizzaId;
        uint256 value = vbtc.subsidyOf(_pizzaId);
        if (value > 0) {
            pointsPerShare += (value * 1e60) / (SLICES_PER_POWER * vbtc.powerOf(_pizzaId));
        }
        return
            uint256(int256(pointsPerShare * slices[poolId][msg.sender]) + pointsCorrection[poolId][msg.sender]) /
            1e60 -
            claimed[poolId][msg.sender];
    }

    function mine(uint256 poolId, uint256 groupBuyingId) external override returns (uint256) {
        if (groupBuyingId == type(uint256).max) {
            return _mine(poolId);
        } else {
            GroupBuying storage groupBuying = groupBuyings[groupBuyingId];
            require(groupBuying.poolId == poolId);

            if (groupBuyingSlices[groupBuyingId][msg.sender] > 0) {
                slices[poolId][msg.sender] += groupBuyingSlices[groupBuyingId][msg.sender];
                delete groupBuyingSlices[groupBuyingId][msg.sender];
            }
            require(slices[poolId][msg.sender] > 0);

            return _mine(poolId);
        }
    }

    function _mine(uint256 poolId) internal returns (uint256) {
        Pool storage pool = pools[poolId];
        uint256 _pizzaId = pool.pizzaId;
        if (pool.lastRewardBlock != block.number) {
            uint256 slicesIn = vbtc.mine(_pizzaId);
            if (slicesIn > 0) updateBalance(pool, slicesIn, (SLICES_PER_POWER * vbtc.powerOf(_pizzaId)));
        }
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

    function suggestGroupBuying(uint256 targetPower, uint256 _slices) external override returns (uint256) {
        require(targetPower > 0);
        uint256 totalSlices = SLICES_PER_POWER * targetPower;
        require(_slices > 0);
        vbtc.transferFrom(msg.sender, address(this), _slices);

        uint256 groupBuyingId = groupBuyings.length;

        groupBuyings.push(
            GroupBuying({poolId: type(uint256).max, targetPower: targetPower, slicesLeft: totalSlices - _slices})
        );
        groupBuyingSlices[groupBuyingId][msg.sender] = _slices;

        emit SuggestGroupBuying(msg.sender, groupBuyingId, _slices);
        return groupBuyingId;
    }

    function participateInGroupBuying(uint256 groupBuyingId, uint256 _slices)
        external
        override
        returns (bool started, uint256 poolId)
    {
        GroupBuying storage groupBuying = groupBuyings[groupBuyingId];
        uint256 newSlicesLeft = groupBuying.slicesLeft - _slices;
        require(newSlicesLeft >= 0);
        require(_slices > 0);

        vbtc.transferFrom(msg.sender, address(this), _slices);
        uint256 newSlices = groupBuyingSlices[groupBuyingId][msg.sender] + _slices;

        groupBuyingSlices[groupBuyingId][msg.sender] = newSlices;

        groupBuying.slicesLeft = newSlicesLeft;

        emit UpdateGroupBuying(msg.sender, groupBuyingId, newSlices);

        if (newSlicesLeft == 0) {
            return _startGroupBuying(groupBuyingId);
        }
        return (false, type(uint256).max);
    }

    function withdrawGroupBuying(uint256 groupBuyingId, uint256 _slices) external override {
        GroupBuying storage groupBuying = groupBuyings[groupBuyingId];

        uint256 _slicesLeft = groupBuying.slicesLeft;
        require(_slicesLeft > 0, "Already started");

        uint256 newSlices = groupBuyingSlices[groupBuyingId][msg.sender] - _slices;
        groupBuyingSlices[groupBuyingId][msg.sender] = newSlices;

        vbtc.transfer(msg.sender, _slices);

        groupBuying.slicesLeft = _slicesLeft + _slices;

        emit UpdateGroupBuying(msg.sender, groupBuyingId, newSlices);
    }

    function _startGroupBuying(uint256 groupBuyingId) internal returns (bool started, uint256 poolId) {
        GroupBuying storage groupBuying = groupBuyings[groupBuyingId];
        uint256 power = groupBuying.targetPower;
        uint256 pizzaId = vbtc.buyPizza(power);
        poolId = pools.length;

        pools.push(
            Pool({
                owner: address(this),
                pizzaId: pizzaId,
                currentBalance: 0,
                pointsPerShare: 0,
                lastRewardBlock: block.number
            })
        );

        pizzaToPool[pizzaId] = poolId;
        groupBuying.poolId = poolId;

        slices[poolId][msg.sender] = groupBuyingSlices[groupBuyingId][msg.sender];
        delete groupBuyingSlices[groupBuyingId][msg.sender];

        emit StartGroupBuying(groupBuyingId);
        emit CreatePool(poolId, address(this), pizzaId, power);
        started = true;
    }
}
