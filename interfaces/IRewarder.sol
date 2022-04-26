// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../contracts/Utils/BoringERC20.sol";

interface IRewarder {
  
    function onSushiReward (uint256 pid, address user, uint256 sushiAmount) external;
    function pendingTokens(uint256 pid, address user, uint256 sushiAmount) external returns (IERC20[] memory , uint256[] memory);
}