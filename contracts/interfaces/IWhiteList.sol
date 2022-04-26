// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ----------------------------------------------------------------------------
// White List interface
// ----------------------------------------------------------------------------

interface IWhiteList {
    function isInWhiteList(address account) external view returns (bool);
    function addWhiteList(address[] calldata accounts) external ;
    function removeWhiteList(address[] calldata accounts) external ;
    function initWhiteList(address accessControl) external ;

}
