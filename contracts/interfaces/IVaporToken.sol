// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
interface IVaporToken {
    function init(bytes calldata data) external payable;
    function initToken( bytes calldata data ) external;
    function tokenTemplate() external view returns (uint256);

}