// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMisoFarm {

    function initFarm(
        bytes calldata data
    ) external;
    function farmTemplate() external view returns (uint256);

}