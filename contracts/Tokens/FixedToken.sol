// SPDX-License-Identifier: MIT    
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "../interfaces/IVaporToken.sol";

contract FixedToken is ERC20, IVaporToken {

    /// @notice Vapor template id for the token factory.
    /// @dev For different token types, this must be incremented.
    uint256 public constant override tokenTemplate = 1;
    
    /// @dev First set the token variables. This can only be done once
    function initToken(string memory _name, string memory _symbol, address _owner, uint256 _initialSupply) public  {
        _initERC20(_name, _symbol);
        _mint(_owner, _initialSupply);
    }
    
    function init(bytes calldata _data) external override payable {}

   function initToken(
        bytes calldata _data
    ) public override {
        (string memory _name,
        string memory _symbol,
        address _owner,
        uint256 _initialSupply) = abi.decode(_data, (string, string, address, uint256));

        initToken(_name,_symbol,_owner,_initialSupply);
    }

   /** 
     * @dev Generates init data for Farm Factory
     * @param _name - Token name
     * @param _symbol - Token symbol
     * @param _owner - Contract owner
     * @param _initialSupply Amount of tokens minted on creation
  */
    function getInitData(
        string calldata _name,
        string calldata _symbol,
        address _owner,
        uint256 _initialSupply
    )
        external
        pure
        returns (bytes memory _data)
    {
        return abi.encode(_name, _symbol, _owner, _initialSupply);
    }


}
