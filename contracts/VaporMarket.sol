// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Access/VaporAccessControls.sol";
import "./Utils/BoringMath.sol";
import "./Utils/SafeTransfer.sol";
import "./interfaces/IVaporMarket.sol";
import "./interfaces/IERC20.sol";
import "./Utils/CloneFactory.sol";
import "hardhat/console.sol";


contract VaporMarket is CloneFactory, SafeTransfer {

    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;

    /// @notice Responsible for access rights to the contract.
    VaporAccessControls public accessControls;
    bytes32 public constant MARKET_MINTER_ROLE = keccak256("MARKET_MINTER_ROLE");

    /// @notice Whether market has been initialized or not.
    bool private initialised;

    /// @notice Struct to track Auction template.
    struct Auction {
        bool exists;
        uint64 templateId;
        uint128 index;
    }

    /// @notice Auctions created using factory.
    address[] public auctions;

    /// @notice Template id to track respective auction template.
    uint256 public auctionTemplateId;

    /// @notice Mapping from market template id to market template address.
    mapping(uint256 => address) private auctionTemplates;

    /// @notice Mapping from market template address to market template id.
    mapping(address => uint256) private auctionTemplateToId;

    // /// @notice mapping from template type to template id
    mapping(uint256 => uint256) public currentTemplateId;

    /// @notice Mapping from auction created through this contract to Auction struct.
    mapping(address => Auction) public auctionInfo;

    /// @notice Struct to define fees.
    struct MarketFees {
        uint128 minimumFee;
        uint32 integratorFeePct;
    }

    /// @notice Minimum fee to create a farm through the factory.
    MarketFees public marketFees;

    /// @notice Contract locked status. If locked, only minters can deploy
    bool public locked;

    ///@notice Any donations if set are sent here.
    address payable public VaporDiv;

    ///@notice Event emitted when first initializing the Market factory.
    event VaporInitMarket(address sender);

    /// @notice Event emitted when template is added to factory.
    event AuctionTemplateAdded(address newAuction, uint256 templateId);

    /// @notice Event emitted when auction template is removed.
    event AuctionTemplateRemoved(address auction, uint256 templateId);

    /// @notice Event emitted when auction is created using template id.
    event MarketCreated(address indexed owner, address indexed addr, address marketTemplate);

    constructor() {
    }

    /**
     * @notice Initializes the market with a list of auction templates.
     * @dev Can only be initialized once.
     * @param _accessControls Sets address to get the access controls from.
     * @param _templates Initial array of VaporMarket templates.
     */
    function initVaporMarket(address _accessControls, address[] memory _templates) external {
        require(!initialised);
        require(_accessControls != address(0), "initVaporMarket: accessControls cannot be set to zero");

        accessControls = VaporAccessControls(_accessControls);

        auctionTemplateId = 0;
        for(uint i = 0; i < _templates.length; i++) {
            _addAuctionTemplate(_templates[i]);
        }
        console.log(auctionTemplateId);
        locked = true;
        initialised = true;
        emit VaporInitMarket(msg.sender);
    }

    /**
     * @notice Sets the minimum fee.
     * @param _amount Fee amount.
     */
    function setMinimumFee(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "VaporMarket: Sender must be operator"
        );
        marketFees.minimumFee = BoringMath.to128(_amount);
    }

    /**
     * @notice Sets the factory to be locked or unlocked.
     * @param _locked bool.
     */
    function setLocked(bool _locked) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "VaporMarket: Sender must be admin"
        );
        locked = _locked;
    }


    /**
     * @notice Sets integrator fee percentage.
     * @param _amount Percentage amount.
     */
    function setIntegratorFeePct(uint256 _amount) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "VaporMarket: Sender must be operator"
        );
        /// @dev this is out of 1000, ie 25% = 250
        require(_amount <= 1000, "VaporMarket: Percentage is out of 1000");
        marketFees.integratorFeePct = BoringMath.to32(_amount);
    }

    /**
     * @notice Sets dividend address.
     * @param _divaddr Dividend address.
     */
    function setDividends(address payable _divaddr) external {
        require(accessControls.hasAdminRole(msg.sender), "VaporMarket.setDev: Sender must be operator");
        require(_divaddr != address(0));
        VaporDiv = _divaddr;
    }

    /**
     * @notice Sets the current template ID for any type.
     * @param _templateType Type of template.
     * @param _templateId The ID of the current template for that type
     */
    function setCurrentTemplateId(uint256 _templateType, uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender),
            "VaporMarket: Sender must be admin"
        );
        currentTemplateId[_templateType] = _templateId;
    }


    /**
     * @notice Used to check whether an address has the minter role
     * @param _address EOA or contract being checked
     * @return bool True if the account has the role or false if it does not
     */
    function hasMarketMinterRole(address _address) public view returns (bool) {
        return accessControls.hasRole(MARKET_MINTER_ROLE, _address);
    }


    /**
     * @notice Creates a new VaporMarket from template _templateId and transfers fees.
     * @param _templateId Id of the crowdsale template to create.
     * @param _integratorFeeAccount Address to pay the fee to.
     * @return newMarket Market address.
     */
    function deployMarket(
        uint256 _templateId,
        address payable _integratorFeeAccount
    )
        public payable returns (address newMarket)
    {
        /// @dev If the contract is locked, only admin and minters can deploy. 
        if (locked) {
            require(accessControls.hasAdminRole(msg.sender) 
                    || accessControls.hasMinterRole(msg.sender)
                    || hasMarketMinterRole(msg.sender),
                "VaporMarket: Sender must be minter if locked"
            );
        }

        MarketFees memory _marketFees = marketFees;
        address auctionTemplate = auctionTemplates[_templateId];
        require(msg.value >= uint256(_marketFees.minimumFee), "VaporMarket: Failed to transfer minimumFee");
        require(auctionTemplate != address(0), "VaporMarket: Auction template doesn't exist");
        uint256 integratorFee = 0;
        uint256 VaporFee = msg.value;
        if (_integratorFeeAccount != address(0) && _integratorFeeAccount != VaporDiv) {
            integratorFee = VaporFee * uint256(_marketFees.integratorFeePct) / 1000;
            VaporFee = VaporFee - integratorFee;
        }

        /// @dev Clone using the Clone Factory. 
        newMarket = createClone(auctionTemplate);
        console.log("auction address: ", address(newMarket));
        auctionInfo[address(newMarket)] = Auction(true, BoringMath.to64(_templateId), BoringMath.to128(auctions.length));
        auctions.push(address(newMarket));
        emit MarketCreated(msg.sender, address(newMarket), auctionTemplate);
        if (VaporFee > 0) {
            VaporDiv.transfer(VaporFee);
        }
        if (integratorFee > 0) {
            _integratorFeeAccount.transfer(integratorFee);
        }
    }

    /**
     * @notice Creates a new VaporMarket using _templateId.
     * @dev Initializes auction with the parameters passed.
     * @param _templateId Id of the auction template to create.
     * @param _token The token address to be sold.
     * @param _tokenSupply Amount of tokens to be sold at market.
     * @param _integratorFeeAccount Address to send refferal bonus, if set.
     * @param _data Data to be sent to template on Init.
     * @return newMarket Market address.
     */
    function createMarket(
        uint256 _templateId,
        address _token,
        uint256 _tokenSupply,
        address payable _integratorFeeAccount,
        bytes calldata _data
    )
        external payable returns (address newMarket)
    {
        newMarket = deployMarket(_templateId, _integratorFeeAccount);
        if (_tokenSupply > 0) {
            _safeTransferFrom(_token, msg.sender, _tokenSupply);
            require(IERC20(_token).approve(newMarket, _tokenSupply), "1");
        }
        IVaporMarket(newMarket).initMarket(_data);

        if (_tokenSupply > 0) {
            uint256 remainingBalance = IERC20(_token).balanceOf(address(this));
            if (remainingBalance > 0) {
                _safeTransfer(_token, msg.sender, remainingBalance);
            }
        }
        return newMarket;
    }

    /**
     * @notice Function to add an auction template to create through factory.
     * @dev Should have operator access.
     * @param _template Auction template to create an auction.
     */
    function addAuctionTemplate(address _template) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "VaporMarket: Sender must be operator"
        );
        _addAuctionTemplate(_template);    
    }

    /**
     * @dev Function to remove an auction template.
     * @dev Should have operator access.
     * @param _templateId Refers to template that is to be deleted.
     */
    function removeAuctionTemplate(uint256 _templateId) external {
        require(
            accessControls.hasAdminRole(msg.sender) ||
            accessControls.hasOperatorRole(msg.sender),
            "VaporMarket: Sender must be operator"
        );
        address template = auctionTemplates[_templateId];
        auctionTemplates[_templateId] = address(0);
        delete auctionTemplateToId[template];
        emit AuctionTemplateRemoved(template, _templateId);
    }

    /**
     * @notice Function to add an auction template to create through factory.
     * @param _template Auction template address to create an auction.
     */
    function _addAuctionTemplate(address _template) private {
        require(
            auctionTemplateToId[_template] == 0,
            "VaporMarket: Template already exists"
        );
        require(auctionTemplateToId[_template] == 0, "VaporMarket: Template already added");
        uint256 templateType = IVaporMarket(_template).marketTemplate();
        require(templateType > 0, "VaporMarket: Incorrect template code ");
        auctionTemplateId++;

        auctionTemplates[auctionTemplateId] = _template;
        auctionTemplateToId[_template] = auctionTemplateId;
        currentTemplateId[templateType] = auctionTemplateId;
        emit AuctionTemplateAdded(_template, auctionTemplateId);
    }

    /**
     * @notice Get the address based on template ID.
     * @param _templateId Auction template ID.
     * @return Address of the required template ID.
     */
    function getAuctionTemplate(uint256 _templateId) external view returns (address) {
        return auctionTemplates[_templateId];
    }

    /**
     * @notice Get the ID based on template address.
     * @param _auctionTemplate Auction template address.
     * @return ID of the required template address.
     */
    function getTemplateId(address _auctionTemplate) external view returns (uint256) {
        return auctionTemplateToId[_auctionTemplate];
    }

    /**
     * @notice Get the total number of auctions in the factory.
     * @return Auction count.
     */
    function numberOfAuctions() external view returns (uint) {
        return auctions.length;
    }

    function minimumFee() external view returns(uint128) {
        return marketFees.minimumFee;
    }

    function getMarkets() external view returns(address[] memory) {
        return auctions;
    }

    function getMarketTemplateId(address _auction) external view returns(uint64) {
        return auctionInfo[_auction].templateId;
    }
}
