// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
interface IVaporLiquidity {
    function initLauncher(
        bytes calldata data
    ) external;

    function getMarkets() external view returns(address[] memory);
    function liquidityTemplate() external view returns (uint256);
}
