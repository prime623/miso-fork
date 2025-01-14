// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
interface IMisoLauncher {
    function createLauncher(
        uint256 _templateId,
        address _token,
        uint256 _tokenSupply,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address newLauncher);

    function currentTemplateId(uint256 tempalateType) external returns (uint256);
}