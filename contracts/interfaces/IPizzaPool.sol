// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

interface IPizzaPool {
    
    event CreatePool(address indexed owner, uint256 indexed poolId, uint256 power, uint256 sliceAllowed, uint256 sliceAllowedPrice, uint256 fee);
    event ChangePool(address indexed owner, uint256 indexed poolId, uint256 power, uint256 sliceAllowed, uint256 sliceAllowedPrice, uint256 fee);
    event DeletePool(address indexed owner, uint256 indexed poolId);
    
    event JoinPool(address indexed owner, uint256 indexed poolId, uint256 amount);

    function poolCount() external view returns (uint256);
    function createPool(uint256 power, uint256 sliceAllowed, uint256 sliceAllowedPrice, uint256 fee) external returns (uint256);
    function changePool(uint256 poolId, uint256 power, uint256 sliceAllowed, uint256 sliceAllowedPrice, uint256 fee) external;
    function deletePool(uint256 poolId) external;
    
    function sliceCount(uint256 poolId) external view returns (uint256);
    function joinPool(uint256 poolId, uint256 amount) external;
    function changeSlice(uint256 poolId, uint256 amount) external;
    function exitPool(uint256 poolId) external;
    
    function subsidyPoolOf(uint256 poolId) external view returns (uint256);
    function claimPool(uint256 poolId) external;
    function subsidySliceOf(uint256 poolId) external view returns (uint256);
    function claimSlice(uint256 poolId) external;
}
