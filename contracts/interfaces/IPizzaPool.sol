// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

interface IPizzaPool {
    event CreatePool(uint256 indexed poolId, address indexed owner, uint256 indexed pizzaId, uint256 power);
    event ChangePool(uint256 indexed poolId, uint256 power);
    event DeletePool(uint256 indexed poolId);

    event Sell(uint256 indexed saleId, address indexed seller, uint256 indexed poolId, uint256 slice, uint256 price);
    event RemoveSale(uint256 indexed saleId);
    event Buy(uint256 indexed saleId, address indexed buyer, uint256 slice);
    event CancelSale(uint256 indexed saleId);

    event Mine(address indexed owner, uint256 indexed poolId, uint256 subsidy);

    event SuggestGroupBuying(address indexed suggester, uint256 indexed groupBuyingId, uint256 slices);

    event UpdateGroupBuying(address indexed participant, uint256 indexed groupBuyingId, uint256 slices);

    event StartGroupBuying(uint256 indexed groupBuyingId);

    function poolCount() external view returns (uint256);

    function pools(uint256 poolId)
        external
        view
        returns (
            address owner,
            uint256 pizzaId,
            uint256 currentBalance,
            uint256 pointsPerShare,
            uint256 lastRewardBlock
        );

    function createPool(uint256 power) external returns (uint256);

    function changePool(uint256 poolId, uint256 power) external;

    function deletePool(uint256 poolId) external;

    function saleCount() external view returns (uint256);

    function sales(uint256 saleId)
        external
        view
        returns (
            address seller,
            uint256 poolId,
            uint256 slice,
            uint256 price
        );

    function sell(
        uint256 poolId,
        uint256 slice,
        uint256 price
    ) external returns (uint256);

    function buy(uint256 saleId, uint256 slice) external;

    function cancelSale(uint256 saleId) external;

    function subsidyOf(uint256 poolId) external view returns (uint256);

    function mine(uint256 poolId) external returns (uint256);

    function groupBuyings(uint256 groupBuyingId)
        external
        view
        returns (
            uint256 poolId,
            uint256 targetPower,
            uint256 slicesLeft
        );

    function groupBuyingSlices(uint256 groupBuyingId, address participant) external view returns (uint256 slices);

    function groupBuyingParticipants(uint256 groupBuyingId) external view returns (address[] calldata participants);

    function suggestGroupBuying(uint256 targetPower, uint256 _slices) external returns (uint256);

    function participateGroupBuying(uint256 groupBuyingId, uint256 _slices)
        external
        returns (bool started, uint256 poolId);

    function withdrawGroupBuying(uint256 groupBuyingId, uint256 _slices) external;
}
