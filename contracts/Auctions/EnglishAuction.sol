// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../OpenZeppelin/utils/ReentrancyGuard.sol";
import "../Access/VaporAccessControls.sol";
import "../Utils/SafeTransfer.sol";
import "../Utils/BoringMath.sol";
import "../Utils/BoringERC20.sol";
import "../Utils/Documents.sol";
import "../interfaces/IPointList.sol";
import "../interfaces/IVaporMarket.sol";
import "hardhat/console.sol";

/// @notice Attribution to delta.financial
/// @notice Attribution to Englishswap.com

contract EnglishAuction is IVaporMarket, VaporAccessControls, SafeTransfer, Documents , ReentrancyGuard  {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringMath64 for uint64;
    using BoringERC20 for IERC20;

    /// @notice VaporMarket template id for the factory contract.
    /// @dev For different marketplace types, this must be incremented.
    uint256 public constant override marketTemplate = 5;

    /// @notice The placeholder ETH address.
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Main market variables.
    struct MarketInfo {
        uint64 startTime;
        uint64 endTime;
        uint128 totalTokens;
    }
    MarketInfo public marketInfo;

    /// @notice Market price variables.
    struct MarketPrice {
        uint128 startPrice;
        uint128 highestBid;
    }
    MarketPrice public marketPrice;

    /// @notice Market dynamic variables.
    struct MarketStatus {
        uint128 bidsTotal;
        bool finalized;
        bool usePointList;
    }

    MarketStatus public marketStatus;

    /// @notice The token being sold.
    address public auctionToken; 
    /// @notice The currency the auction accepts for payment. Can be ETH or token address.
    address public paymentCurrency;  
    /// @notice Where the auction funds will get paid.
    address payable public wallet;  
    /// @notice Address that manages auction approvals.
    address public pointList;
    /// @notice Address of the highest commiter.
    address public highestBidder;



    /// @notice The commited amount of accounts.
    mapping(address => uint256) public bids; 
    /// @notice Amount of tokens to claim per address.
    mapping(address => uint256) public claimed;

    /// @notice Event for updating auction times.  Needs to be before auction starts.
    event AuctionTimeUpdated(uint256 startTime, uint256 endTime); 
    /// @notice Event for updating auction price. Needs to be before auction starts.
    event AuctionPriceUpdated(uint256 startPrice); 
    /// @notice Event for updating auction wallet. Needs to be before auction starts.
    event AuctionWalletUpdated(address wallet); 

    /// @notice Event for adding a commitment.
    event AddedCommitment(address indexed addr, uint256 commitment);   
    /// @notice Event for finalization of the auction.
    event AuctionFinalized();
    /// @notice Event for cancellation of the auction.
    event AuctionCancelled();

    /**
     * @notice Initializes main contract variables and transfers funds for the auction.
     * @dev Init function.
     * @param _funder The address that funds the token for crowdsale.
     * @param _token Address of the token being sold.
     * @param _totalTokens The total number of tokens to sell in auction.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     * @param _paymentCurrency The currency the crowdsale accepts for payment. Can be ETH or token address.
     * @param _startPrice Starting price of the auction.
     * @param _admin Address that can finalize auction.
     * @param _pointList Address that will manage auction approvals.
     * @param _wallet Address where collected funds will be forwarded to.
     */
    function initAuction(
        address _funder,
        address _token,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        address _paymentCurrency,
        uint256 _startPrice,
        address _admin,
        address _pointList,
        address payable _wallet
    ) public {
        require(_startTime < 10000000000, "EnglishAuction: enter an unix timestamp in seconds, not miliseconds");
        require(_endTime < 10000000000, "EnglishAuction: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "EnglishAuction: start time is before current time");
        require(_endTime > _startTime, "EnglishAuction: end time must be older than start price");
        require(_totalTokens > 0,"EnglishAuction: total tokens must be greater than zero");
        require(_startPrice > 0, "EnglishAuction: start price must be higher than minimum price");
        require(_admin != address(0), "EnglishAuction: admin is the zero address");
        require(_wallet != address(0), "EnglishAuction: wallet is the zero address");
        require(IERC20(_token).decimals() == 18, "EnglishAuction: Token does not have 18 decimals");
        if (_paymentCurrency != ETH_ADDRESS) {
            require(IERC20(_paymentCurrency).decimals() > 0, "EnglishAuction: Payment currency is not ERC20");
        }

        marketInfo.startTime = BoringMath.to64(_startTime);
        marketInfo.endTime = BoringMath.to64(_endTime);
        marketInfo.totalTokens = BoringMath.to128(_totalTokens);

        marketPrice.startPrice = BoringMath.to128(_startPrice);
        marketPrice.highestBid = BoringMath.to128(_startPrice);

        auctionToken = _token;
        paymentCurrency = _paymentCurrency;
        wallet = _wallet;

        console.log(block.timestamp);
        console.log(_startTime);
        initAccessControls(_admin);

        _setList(_pointList);
        _safeTransferFrom(_token, _funder, _totalTokens);
    }

    /**
     * @notice Calculates the average price of each token from all bids.
     * @return Average token price.
     */
    function averageTokenPrice() public view returns (uint256) {
        return uint256(marketStatus.bidsTotal)
            .mul(1e18).div(uint256(marketInfo.totalTokens));
    }

    /**
     * @notice Returns auction price in any time.
     * @return Fixed start price or highest commitment.
     */
    function priceFunction() public view returns (uint256) {
        /// @dev Return Auction Price
        if (block.timestamp <= uint256(marketInfo.startTime)) {
            return uint256(marketPrice.startPrice);
        } else {
            return uint256(marketPrice.highestBid);
        }
    }

    /**
     * @notice The clearing price of the English auction.
     */
    function currentPrice() public view returns (uint256) {
        return(marketPrice.highestBid);
    }


    ///--------------------------------------------------------
    /// Commit to buying tokens!
    ///--------------------------------------------------------

    receive() external payable {
        revertBecauseUserDidNotProvideAgreement();
    }

    /** 
     * @dev Attribution to the awesome delta.financial contracts
    */  
    function marketParticipationAgreement() public pure returns (string memory) {
        return "I understand that I'm interacting with a smart contract. I understand that tokens commited are subject to the token issuer and local laws where applicable. I reviewed code of the smart contract and understand it fully. I agree to not hold developers or other people associated with the project liable for any losses or misunderstandings";
    }
    /** 
     * @dev Not using modifiers is a purposeful choice for code readability.
    */ 
    function revertBecauseUserDidNotProvideAgreement() internal pure {
        revert("No agreement provided, please review the smart contract before interacting with it");
    }

    /**
     * @notice Checks the amount of ETH to commit and adds the commitment. Refunds the buyer if commit is too high.
     * @param _beneficiary Auction participant ETH address.
     */
    function bidEth(
        address payable _beneficiary,
        bool readAndAgreedToMarketParticipationAgreement
    )
        public payable nonReentrant
    {
        require(paymentCurrency == ETH_ADDRESS, "EnglishAuction: payment currency is not ETH address"); 
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        require(msg.value > marketPrice.highestBid, "Bid needs to be higher than the previous.");
        
        _addCommitment(_beneficiary, msg.value);
        
    }

    /**
     * @notice Buy Tokens by commiting approved ERC20 tokens to this contract address.
     * @param _amount Amount of tokens to commit.
     */
    function bidTokens(uint256 _amount, bool readAndAgreedToMarketParticipationAgreement) public {
        bidTokensFrom(msg.sender, _amount, readAndAgreedToMarketParticipationAgreement);
    }


    /**
     * @notice Checks how much is user able to commit and processes that commitment.
     * @dev Users must approve contract prior to committing tokens to auction.
     * @param _from User ERC20 address.
     * @param _amount Amount of approved ERC20 tokens.
     */
    function bidTokensFrom(
        address _from,
        uint256 _amount,
        bool readAndAgreedToMarketParticipationAgreement
    )
        public   nonReentrant  
    {
        require(address(paymentCurrency) != ETH_ADDRESS, "EnglishAuction: Payment currency is not a token");
        require(_amount > marketPrice.highestBid, "Your bid has to higher than the previous one.");
        if(readAndAgreedToMarketParticipationAgreement == false) {
            revertBecauseUserDidNotProvideAgreement();
        }
        
        _addCommitment(_from, _amount);
        _safeTransferFrom(paymentCurrency, _from, _amount);
        
    }
   /**
     * @notice How many tokens the user is able to claim.
     * @param _user Auction participant address.
     * @return claimerCommitment User bids reduced by already claimed tokens.
     */
    function tokensClaimable(address _user) public view returns (uint256 claimerCommitment) {
        if (bids[_user] == 0) return 0;
        uint256 unclaimedTokens = IERC20(auctionToken).balanceOf(address(this));

        claimerCommitment = bids[_user].mul(uint256(marketInfo.totalTokens)).div(uint256(marketStatus.bidsTotal));
        claimerCommitment = claimerCommitment.sub(claimed[_user]);

        if(claimerCommitment > unclaimedTokens){
            claimerCommitment = unclaimedTokens;
        }
    }

    /**
     * @notice Calculates total amount of tokens committed at current auction price.
     * @return Number of tokens commited.
     */
    function totalTokensCommitted() public view returns (uint256) {
        return uint256(marketStatus.bidsTotal).mul(1e18).div(currentPrice());
    }

    /**
     * @notice Checks if the auction is open.
     * @return True if current time is greater than startTime and less than endTime.
     */
    function isOpen() public view returns (bool) {
        return block.timestamp >= uint256(marketInfo.startTime) && block.timestamp <= uint256(marketInfo.endTime);
    }

    /**
     * @notice Successful if tokens sold equals totalTokens.
     * @return True if tokenPrice is bigger or equal currentPrice.
     */
    function auctionSuccessful() public view returns (bool) {
        return block.timestamp >= uint256(marketInfo.endTime);
    }

    /**
     * @notice Checks if the auction has ended.
     * @return True if auction is successful or time has ended.
     */
    function auctionEnded() public view returns (bool) {
        return auctionSuccessful() || block.timestamp > uint256(marketInfo.endTime);
    }

    /**
     * @return Returns true if market has been finalized
     */
    function finalized() public view returns (bool) {
        return marketStatus.finalized;
    }

    /**
     * @return Returns true if 14 days have passed since the end of the auction
     */
    function finalizeTimeExpired() public view returns (bool) {
        return uint256(marketInfo.endTime) + 7 days < block.timestamp;
    }

    /**
     * @notice Updates commitment for this address and total commitment of the auction.
     * @param _addr Bidders address.
     * @param _bid The amount to commit.
     */
   
    function _addCommitment(address _addr, uint256 _bid) internal {
        require(block.timestamp >= uint256(marketInfo.startTime) && block.timestamp <= uint256(marketInfo.endTime), "EnglishAuction: outside auction hours");
        require(_addr == msg.sender, "Wrong address.");
        MarketStatus storage status = marketStatus;
        
        marketPrice.highestBid = BoringMath.to128(_bid);
        highestBidder = _addr;
        uint256 newBid = bids[_addr].add(_bid);
       /* if (status.usePointList) {
            require(IPointList(pointList).hasPoints(_addr, newBid));
        } */
        
        bids[_addr] = newBid;
        console.log(bids[_addr]);
        status.bidsTotal = BoringMath.to128(uint256(status.bidsTotal).add(_bid));
        emit AddedCommitment(_addr, _bid);
    }


    //--------------------------------------------------------
    // Finalize Auction
    //--------------------------------------------------------


    /**
     * @notice Cancel Auction
     * @dev Admin can cancel the auction before it starts
     */
    function cancelAuction() public   nonReentrant  
    {
        require(hasAdminRole(msg.sender));
        MarketStatus storage status = marketStatus;
        require(!status.finalized, "EnglishAuction: auction already finalized");
        require( uint256(status.bidsTotal) == 0, "EnglishAuction: auction already committed" );
        _safeTokenPayment(auctionToken, wallet, uint256(marketInfo.totalTokens));
        status.finalized = true;
        emit AuctionCancelled();
    }

    /**
     * @notice Auction finishes successfully above the reserve.
     * @dev Transfer contract funds to initialized wallet.
     */
    function finalize() public   nonReentrant  
    {

        require(hasAdminRole(msg.sender) 
                || hasSmartContractRole(msg.sender) 
                || wallet == msg.sender
                || finalizeTimeExpired(), "EnglishAuction: sender must be an admin");
        MarketStatus storage status = marketStatus;

        require(!status.finalized, "EnglishAuction: auction already finalized");
        if (auctionSuccessful()) {
            /// @dev Successful auction
            /// @dev Transfer contributed tokens to wallet.
            _safeTokenPayment(paymentCurrency, wallet, uint256(status.bidsTotal));
        } else {
            /// @dev Failed auction
            /// @dev Return auction tokens back to wallet.
            require(block.timestamp > uint256(marketInfo.endTime), "EnglishAuction: auction has not finished yet"); 
            _safeTokenPayment(auctionToken, wallet, uint256(marketInfo.totalTokens));
        }
        status.finalized = true;
        emit AuctionFinalized();
    }


    /// @notice Withdraws bought tokens, or returns commitment if the sale is unsuccessful.
    function withdrawTokens() public  {
        withdrawTokens(payable(msg.sender));
    }

   /**
     * @notice Withdraws bought tokens, or returns commitment if the sale is unsuccessful.
     * @dev Withdraw tokens only after auction ends.
     * @param beneficiary Whose tokens will be withdrawn.
     */
    function withdrawTokens(address payable beneficiary) public   nonReentrant  {
        if (auctionSuccessful()) {
            require(marketStatus.finalized, "EnglishAuction: not finalized");
            /// @dev Successful auction! Transfer claimed tokens.
            uint256 tokensToClaim = tokensClaimable(beneficiary);
            require(tokensToClaim > 0, "EnglishAuction: No tokens to claim"); 
            claimed[beneficiary] = claimed[beneficiary].add(tokensToClaim);
            _safeTokenPayment(auctionToken, beneficiary, tokensToClaim);
        } else {
            /// @dev Auction did not meet reserve price.
            /// @dev Return committed funds back to user.
            require(block.timestamp > uint256(marketInfo.endTime), "EnglishAuction: auction has not finished yet");
            uint256 fundsCommitted = bids[beneficiary];
            bids[beneficiary] = 0; // Stop multiple withdrawals and free some gas
            _safeTokenPayment(paymentCurrency, beneficiary, fundsCommitted);
        }
    }


    //--------------------------------------------------------
    // Documents
    //--------------------------------------------------------

    function setDocument(string calldata _name, string calldata _data) external {
        require(hasAdminRole(msg.sender) );
        _setDocument( _name, _data);
    }

    function setDocuments(string[] calldata _name, string[] calldata _data) external {
        require(hasAdminRole(msg.sender) );
        uint256 numDocs = _name.length;
        for (uint256 i = 0; i < numDocs; i++) {
            _setDocument( _name[i], _data[i]);
        }
    }

    function removeDocument(string calldata _name) external {
        require(hasAdminRole(msg.sender));
        _removeDocument(_name);
    }


    //--------------------------------------------------------
    // Point Lists
    //--------------------------------------------------------


    function setList(address _list) external {
        require(hasAdminRole(msg.sender));
        _setList(_list);
    }

    function enableList(bool _status) external {
        require(hasAdminRole(msg.sender));
        marketStatus.usePointList = _status;
    }

    function _setList(address _pointList) private {
        if (_pointList != address(0)) {
            pointList = _pointList;
            marketStatus.usePointList = true;
        }
    }

    //--------------------------------------------------------
    // Setter Functions
    //--------------------------------------------------------

    /**
     * @notice Admin can set start and end time through this function.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     */
    function setAuctionTime(uint256 _startTime, uint256 _endTime) external {
        require(hasAdminRole(msg.sender));
        require(_startTime < 10000000000, "EnglishAuction: enter an unix timestamp in seconds, not miliseconds");
        require(_endTime < 10000000000, "EnglishAuction: enter an unix timestamp in seconds, not miliseconds");
        require(_startTime >= block.timestamp, "EnglishAuction: start time is before current time");
        require(_endTime > _startTime, "EnglishAuction: end time must be older than start time");
        require(marketStatus.bidsTotal == 0, "EnglishAuction: auction cannot have already started");

        marketInfo.startTime = BoringMath.to64(_startTime);
        marketInfo.endTime = BoringMath.to64(_endTime);
        
        emit AuctionTimeUpdated(_startTime,_endTime);
    }

    /**
     * @notice Admin can set start price through this function.
     * @param _startPrice Auction start price.
     */
    function setAuctionPrice(uint256 _startPrice) external {
        require(hasAdminRole(msg.sender));
        require(_startPrice > 0, "EnglishAuction: start price must be greater than 0");
        require(marketStatus.bidsTotal == 0, "EnglishAuction: auction cannot have already started");

        marketPrice.startPrice = BoringMath.to128(_startPrice);

        emit AuctionPriceUpdated(_startPrice);
    }

    /**
     * @notice Admin can set the auction wallet through this function.
     * @param _wallet Auction wallet is where funds will be sent.
     */
    function setAuctionWallet(address payable _wallet) external {
        require(hasAdminRole(msg.sender));
        require(_wallet != address(0), "EnglishAuction: wallet is the zero address");

        wallet = _wallet;

        emit AuctionWalletUpdated(_wallet);
    }


   //--------------------------------------------------------
    // Market Launchers
    //--------------------------------------------------------

    /**
     * @notice Decodes and hands auction data to the initAuction function.
     * @param _data Encoded data for initialization.
     */

    function init(bytes calldata _data) external override payable {

    }

    function initMarket(
        bytes calldata _data
    ) public override {
        (
        address _funder,
        address _token,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        address _paymentCurrency,
        uint256 _startPrice,
        address _admin,
        address _pointList,
        address payable _wallet
        ) = abi.decode(_data, (
            address,
            address,
            uint256,
            uint256,
            uint256,
            address,
            uint256,
            address,
            address,
            address
        ));
        initAuction(_funder, _token, _totalTokens, _startTime, _endTime, _paymentCurrency, _startPrice, _admin, _pointList, _wallet);
    }

    /**
     * @notice Collects data to initialize the auction and encodes them.
     * @param _funder The address that funds the token for crowdsale.
     * @param _token Address of the token being sold.
     * @param _totalTokens The total number of tokens to sell in auction.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     * @param _paymentCurrency The currency the crowdsale accepts for payment. Can be ETH or token address.
     * @param _startPrice Starting price of the auction.
     * @param _admin Address that can finalize auction.
     * @param _pointList Address that will manage auction approvals.
     * @param _wallet Address where collected funds will be forwarded to.
     * @return _data All the data in bytes format.
     */
    function getAuctionInitData(
        address _funder,
        address _token,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime,
        address _paymentCurrency,
        uint256 _startPrice,
        address _admin,
        address _pointList,
        address payable _wallet
    )
        external 
        pure
        returns (bytes memory _data)
    {
            return abi.encode(
                _funder,
                _token,
                _totalTokens,
                _startTime,
                _endTime,
                _paymentCurrency,
                _startPrice,
                _admin,
                _pointList,
                _wallet
            );
    }
        
    function getBaseInformation() external view returns(
        address, 
        uint64,
        uint64,
        bool,
        uint128 
    ) {
        return (auctionToken, marketInfo.startTime, marketInfo.endTime, marketStatus.finalized, marketPrice.highestBid);
    }

    function getTotalTokens() external view returns(uint256) {
        return uint256(marketInfo.totalTokens);
    }


}
