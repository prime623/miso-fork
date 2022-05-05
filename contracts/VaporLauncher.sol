// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//----------------------------------------------------------------------------------
//    I n s t a n t
//
//        .:mmm.         .:mmm:.       .ii.  .:SSSSSSSSSSSSS.     .oOOOOOOOOOOOo.  
//      .mMM'':Mm.     .:MM'':Mm:.     .II:  :SSs..........     .oOO'''''''''''OOo.
//    .:Mm'   ':Mm.   .:Mm'   'MM:.    .II:  'sSSSSSSSSSSSSS:.  :OO.           .OO:
//  .'mMm'     ':MM:.:MMm'     ':MM:.  .II:  .:...........:SS.  'OOo:.........:oOO'
//  'mMm'        ':MMmm'         'mMm:  II:  'sSSSSSSSSSSSSS'     'oOOOOOOOOOOOO'  
//
//----------------------------------------------------------------------------------
//
// Chef Gonpachi's Vapor Launcher
//
// A factory to conveniently deploy your own liquidity contracts
//
// Inspired by Bokky's EtherVendingMachince.io
// https://github.com/bokkypoobah/FixedSupplyTokenFactory
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// The above copyright notice and this permission notice shall be included 
// in all copies or substantial portions of the Software.
//
// Made for Sushi.com 
// 
// Enjoy. (c) Chef Gonpachi 2021 
// <https://github.com/chefgonpachi/Vapor/>
//
// ---------------------------------------------------------------------
                     
// ---------------------------------------------------------------------

import "./Utils/SafeTransfer.sol";
import "./Utils/BoringMath.sol";
import "./Access/VaporAccessControls.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IVaporLiquidity.sol";
import "./interfaces/IBentoBoxFactory.sol";


contract VaporLauncher is SafeTransfer {

    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;

    /// @notice Responsible for access rights to the contract.
    VaporAccessControls public accessControls;
    bytes32 public constant LAUNCHER_MINTER_ROLE = keccak256("LAUNCHER_MINTER_ROLE");

    /// @notice Whether launcher has been initialized or not.
    bool private initialised;

    /// @notice Struct to track Auction template.
    struct Launcher {
        bool exists;
        uint64 templateId;
        uint128 index;
    }

    /// @notice All the launchers created using factory.
    address[] public launchers;

    /// @notice Template id to track respective auction template.
    uint256 public launcherTemplateId;

    /// @notice Address for Wrapped Ether.
    address public WETH;
    IBentoBoxFactory public bentoBox;

    /// @notice Mapping from template id to launcher template address.
    mapping(uint256 => address) private launcherTemplates;

    /// @notice mapping from launcher template address to launcher template id
    mapping(address => uint256) private launcherTemplateToId;

    // /// @notice mapping from template type to template id
    mapping(uint256 => uint256) public currentTemplateId;

    /// @notice Mapping from auction created through this contract to Auction struct.
    mapping(address => Launcher) public launcherInfo;

    /// @notice Struct to define fees.
    struct LauncherFees {
        uint128 minimumFee;
        uint32 integratorFeePct;
    }

    /// @notice Minimum fee to create a launcher through the factory.
    LauncherFees public launcherFees;

    /// @notice Contract locked status. If locked, only minters can deploy
    bool public locked;

    ///@notice Any donations if set are sent here.
    address payable public VaporDiv;

    /// @notice Event emitted when first intializing the liquidity launcher.
    event VaporInitLauncher(address sender);

    /// @notice Event emitted when launcher is created using template id.
    event LauncherCreated(address indexed owner, address indexed addr, address launcherTemplate);

    /// @notice Event emitted when launcher template is added to factory.
    event LauncherTemplateAdded(address newLauncher, uint256 templateId);

    /// @notice Event emitted when launcher template is removed.
    event LauncherTemplateRemoved(address launcher, uint256 templateId);

    constructor() {
    }

    /**
     * @notice Single gateway to initialize the Vapor Launcher with proper address.
     * @dev Can only be initialized once.
     * @param _accessControls Sets address to get the access controls from.
     */
    function initVaporLauncher(address _accessControls, address _WETH, address _bentoBox) external {
        require(!initialised);
        require(_WETH != address(0), "initVaporLauncher: WETH cannot be set to zero");
        require(_accessControls != address(0), "initVaporLauncher: accessControls cannot be set to zero");
        require(_bentoBox != address(0), "initVaporLauncher: bentoBox cannot be set to zero");

        accessControls = VaporAccessControls(_accessControls);
        bentoBox = IBentoBoxFactory(_bentoBox); 
        WETH = _WETH;
        locked = true;
        initialised = true;

        emit VaporInitLauncher(msg.sender);
    }

    /**
     * @notice Sets the minimum fee.
     * @param _amount Fee amount.
     */
    function setMinimumFee(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "VaporLauncher: Sender must be operator"
        );
        launcherFees.minimumFee = BoringMath.to128(_amount);
    }

    /**
     * @notice Sets integrator fee percentage.
     * @param _amount Percentage amount.
     */
    function setIntegratorFeePct(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "VaporLauncher: Sender must be operator"
        );
        /// @dev this is out of 1000, ie 25% = 250
        require(_amount <= 1000, "VaporLauncher: Percentage is out of 1000");
        launcherFees.integratorFeePct = BoringMath.to32(_amount);
    }

    /**
     * @notice Sets dividend address.
     * @param _divaddr Dividend address.
     */
    function setDividends(address payable _divaddr) external {
        require(accessControls.hasAdminRole(msg.sender), "VaporLauncher.setDev: Sender must be operator");
        require(_divaddr != address(0));
        VaporDiv = _divaddr;
    }
    /**
     * @notice Sets the factory to be locked or unlocked.
     * @param _locked bool.
     */
    function setLocked(bool _locked) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "VaporLauncher: Sender must be admin"
        );
        locked = _locked;
    }

    /**
     * @notice Sets the current template ID for any type.
     * @param _templateType Type of template.
     * @param _templateId The ID of the current template for that type
     */
    function setCurrentTemplateId(uint256 _templateType, uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "VaporLauncher: Sender must be admin"
        );
        currentTemplateId[_templateType] = _templateId;
    }

    /**
     * @notice Used to check whether an address has the minter role
     * @param _address EOA or contract being checked
     * @return bool True if the account has the role or false if it does not
     */
    function hasLauncherMinterRole(address _address) public view returns (bool) {
        return accessControls.hasRole(LAUNCHER_MINTER_ROLE, _address);
    }



    /**
     * @notice Creates a launcher corresponding to _templateId.
     * @param _templateId Template id of the launcher to create.
     * @param _integratorFeeAccount Address to pay the fee to.
     * @return launcher  Launcher address.
     */
    function deployLauncher(
        uint256 _templateId,
        address payable _integratorFeeAccount
    )
        public payable returns (address launcher)
    {
        /// @dev If the contract is locked, only admin and minters can deploy. 
        if (locked) {
            require(accessControls.hasAdminRole(msg.sender) 
                    || accessControls.hasMinterRole(msg.sender)
                    || hasLauncherMinterRole(msg.sender),
                "VaporLauncher: Sender must be minter if locked"
            );
        }

        LauncherFees memory _launcherFees = launcherFees;
        address launcherTemplate = launcherTemplates[_templateId];
        require(msg.value >= uint256(_launcherFees.minimumFee), "VaporLauncher: Failed to transfer minimumFee");
        require(launcherTemplate != address(0), "VaporLauncher: Launcher template doesn't exist");
        uint256 integratorFee = 0;
        uint256 VaporFee = msg.value;
        if (_integratorFeeAccount != address(0) && _integratorFeeAccount != VaporDiv) {
            integratorFee = VaporFee * uint256(_launcherFees.integratorFeePct) / 1000;
            VaporFee = VaporFee - integratorFee;
        }
        /// @dev Deploy using the BentoBox factory. 
        launcher = bentoBox.deploy(launcherTemplate, "", false);
        launcherInfo[address(launcher)] = Launcher(true, BoringMath.to64(_templateId), BoringMath.to128(launchers.length));
        launchers.push(address(launcher));
        emit LauncherCreated(msg.sender, address(launcher), launcherTemplates[_templateId]);
        if (VaporFee > 0) {
            VaporDiv.transfer(VaporFee);
        }
        if (integratorFee > 0) {
            _integratorFeeAccount.transfer(integratorFee);
        }
    }


    /**
     * @notice Creates a new VaporLauncher using _templateId.
     * @dev Initializes auction with the parameters passed.
     * @param _templateId Id of the auction template to create.
     * @param _token The token address to be sold.
     * @param _tokenSupply Amount of tokens to be sold at market.
     * @param _integratorFeeAccount Address to send refferal bonus, if set.
     * @param _data Data to be sent to template on Init.
     * @return newLauncher Launcher address.
     */
    function createLauncher(
        uint256 _templateId,
        address _token,
        uint256 _tokenSupply,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address newLauncher)
    {

        newLauncher = deployLauncher(_templateId, _integratorFeeAccount);
        if (_tokenSupply > 0) {
            _safeTransferFrom(_token, msg.sender, _tokenSupply);
            require(IERC20(_token).approve(newLauncher, _tokenSupply), "1");
        }
        IVaporLiquidity(newLauncher).initLauncher(_data);

        if (_tokenSupply > 0) {
            uint256 remainingBalance = IERC20(_token).balanceOf(address(this));
            if (remainingBalance > 0) {
                _safeTransfer(_token, msg.sender, remainingBalance);
            }
        }
        return newLauncher;
    }


    /**
     * @notice Function to add a launcher template to create through factory.
     * @dev Should have operator access
     * @param _template Launcher template address.
    */
    function addLiquidityLauncherTemplate(address _template) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "VaporLauncher: Sender must be operator"
        );
        uint256 templateType = IVaporLiquidity(_template).liquidityTemplate();
        require(templateType > 0, "VaporLauncher: Incorrect template code ");
        launcherTemplateId++;

        launcherTemplates[launcherTemplateId] = _template;
        launcherTemplateToId[_template] = launcherTemplateId;
        currentTemplateId[templateType] = launcherTemplateId;
        emit LauncherTemplateAdded(_template, launcherTemplateId);

    }

    /**
     * @dev Function to remove a launcher template from factory.
     * @dev Should have operator access.
     * @param _templateId Id of the template to be deleted.
     */
    function removeLiquidityLauncherTemplate(uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "VaporLauncher: Sender must be operator"
        );
        require(launcherTemplates[_templateId] != address(0));
        address _template = launcherTemplates[_templateId];
        launcherTemplates[_templateId] = address(0);
        delete launcherTemplateToId[_template];
        emit LauncherTemplateRemoved(_template, _templateId);
    }

    /**
     * @notice Get the address based on launcher template ID.
     * @param _templateId Launcher template ID.
     * @return address of the required template ID.
     */
    function getLiquidityLauncherTemplate(uint256 _templateId) external view returns (address) {
        return launcherTemplates[_templateId];
    }

    function getTemplateId(address _launcherTemplate) external view returns (uint256) {
        return launcherTemplateToId[_launcherTemplate];
    }

    /**
     * @notice Get the total number of launchers in the contract.
     * @return uint256 Launcher count.
     */
    function numberOfLiquidityLauncherContracts() external view returns (uint256) {
        return launchers.length;
    }

    function minimumFee() external view returns(uint128) {
        return launcherFees.minimumFee;
    }

    function getLauncherTemplateId(address _launcher) external view returns(uint64) {
        return launcherInfo[_launcher].templateId;
    }
    function getLaunchers() external view returns(address[] memory) {
        return launchers;
    }


}
