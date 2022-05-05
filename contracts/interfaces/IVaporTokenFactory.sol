// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
interface IVaporTokenFactory {
    function numberOfTokens() external view returns (uint256);
    function getTokens() external view returns (address[] memory);
}