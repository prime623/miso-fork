// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./ISafeGnosis.sol";
interface IGnosisProxyFactory {
    function createProxy(
        ISafeGnosis masterCopy, bytes memory data) external returns(ISafeGnosis proxy);

 
}

