// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
    constructor() {
        _transferOwnership(_msgSender());
    }
    */

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    /*
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    */
    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract ActivatedByOwner is Ownable {
    bool public active = true;

    function setActive(bool _active) public  onlyOwner
    {
        active = _active;
    }

    modifier onlyActive
    {
        require(active, "This contract is deactivated by owner");
        _;
    }
}

interface NFTInterface {
    function mintWithClass(uint256 classId) external returns (uint256 _newTokenID);
    function transfer(address _to, uint256 _tokenId, bytes calldata _data) external returns (bool);
    function addPropertyWithContent(uint256 _tokenId, string calldata _content) external;
}

contract NFTMulticlassBiddableAuction is ActivatedByOwner {

    event AuctionCreated(uint256 indexed tokenClassAuctionID, uint256 timestamp);
    //event TokenSold(uint256 indexed tokenID, uint256 indexed tokenClassID, address indexed buyer);
    event NFTContractSet(address indexed newNFTContract, address indexed oldNFTContract);
    event RevenueWithdrawal(uint256 amount);
    event RoundEnd(uint256 indexed tokenClassAuctionID, address indexed winner, uint256 indexed acquiredTokenID);
    event NewRound(uint256 indexed tokenClassAuctionID, uint256 indexed startTimestamp, uint256 indexed endTimestamp);

    address public nft_contract;

    struct NFTBiddableAuctionClass
    {
        uint256 max_supply;
        uint256 amount_sold;
        uint256 start_timestamp;
        uint256 duration;
        uint256 min_priceInWei;
        uint256 highest_bid;
        address winner;
        string[] configuratin_properties;
    }

    struct NFTBidClass
    {
        uint256 classID;
        address owner;
        uint256 bid_amount;
        uint256 bid_timestamp;
    }

    mapping (uint256 => NFTBidClass) public bids; // Mapping all bids
    uint256 public nextBidIndex = 0; //Bids index

    mapping (uint256 => NFTBiddableAuctionClass) public auctions; // Mapping from classID (at NFT contract) to set of variables
                                                                  //  defining the auction for this token class.
    uint256 public revenue_amount; // total amount of revenue

    address payable public revenue = payable(0x01000B5fE61411C466b70631d7fF070187179Bbf); // This address has the rights to withdraw funds from the auction.

    constructor()
    {
        _owner = msg.sender;
    }

    function createNFTAuction(
        uint256 _classID, 
        uint256 _max_supply, 
        uint256 _start_timestamp, 
        uint256 _duration, 
        uint256 _minPriceInWEI,
        uint256 _already_sold 
    ) public onlyOwner
    {
        auctions[_classID].max_supply      = _max_supply;
        auctions[_classID].amount_sold     = _already_sold;
        auctions[_classID].start_timestamp = _start_timestamp;
        auctions[_classID].duration        = _duration;
        auctions[_classID].min_priceInWei  = _minPriceInWEI;
        auctions[_classID].winner          = owner();

        emit AuctionCreated(_classID, block.timestamp);
    }

    function setRevenueAddress(address payable _revenue_address) public onlyOwner {
        revenue = _revenue_address;
    }

    function setNFTContract(address _nftContract) public onlyOwner
    {
        emit NFTContractSet(nft_contract, _nftContract);

        nft_contract = _nftContract;
    }
    
    function bidOnNFT(uint256 _classID) public payable onlyActive
    {

        uint256 _bid = msg.value;

        require(_bid >= auctions[_classID].min_priceInWei, "Min price criteria is not met");
        require(auctions[_classID].start_timestamp < block.timestamp, "Auction did not start yet");

        if(auctions[_classID].start_timestamp + auctions[_classID].duration < block.timestamp)
        {
            endRound(_classID);
            payable(msg.sender).transfer(_bid - auctions[_classID].min_priceInWei);
            _bid = auctions[_classID].min_priceInWei;
        }

        require(auctions[_classID].max_supply > auctions[_classID].amount_sold, "All NFTs of this artwork are already sold");

        require(
            _bid >= auctions[_classID].highest_bid + auctions[_classID].highest_bid/20 && 
            _bid >= auctions[_classID].highest_bid + 1e18,
            "Does not outbid current winner by 5%"
        );
        require(auctions[_classID].min_priceInWei != 0, "Min price is not configured by the owner");

        payable(auctions[_classID].winner).transfer(auctions[_classID].highest_bid);

        auctions[_classID].winner      = msg.sender;
        auctions[_classID].highest_bid = _bid;

        bids[nextBidIndex].classID = _classID;
        bids[nextBidIndex].owner = msg.sender;
        bids[nextBidIndex].bid_amount = _bid;
        bids[nextBidIndex].bid_timestamp = block.timestamp;

        nextBidIndex++;

    }

    function resetRound(uint256 _classID) internal
    {
        auctions[_classID].winner          = owner();
        auctions[_classID].highest_bid     = 0;
        auctions[_classID].start_timestamp = block.timestamp + 600;

        emit NewRound(_classID, auctions[_classID].start_timestamp, auctions[_classID].start_timestamp + auctions[_classID].duration);
    }

    function endRound(uint256 _classID) public
    {
        require(block.timestamp > auctions[_classID].start_timestamp + auctions[_classID].duration, "Auction is still in progress");
        require(auctions[_classID].max_supply > auctions[_classID].amount_sold, "All NFTs of this artwork are already sold");
        auctions[_classID].amount_sold++;

        uint256 _mintedId = NFTInterface(nft_contract).mintWithClass(_classID);
        configureNFT(_mintedId, _classID);

        NFTInterface(nft_contract).transfer(auctions[_classID].winner, _mintedId, "");

        emit RoundEnd(_classID, auctions[_classID].winner, _mintedId);
        revenue_amount += auctions[_classID].highest_bid;

        if(auctions[_classID].amount_sold != auctions[_classID].max_supply)
        {
            resetRound(_classID);
        }
    }

    function configureNFT(uint256 _tokenId, uint256 _classId) internal
    {
        //Add Serial Number to the created Token
        uint256 tokenSerialNumber = auctions[_classId].amount_sold;
        NFTInterface(nft_contract).addPropertyWithContent(_tokenId, toString(tokenSerialNumber));
    }

    function withdrawRevenue() public onlyOwner
    {
        require(msg.sender == revenue, "This action requires revenue permission");

        uint256 toPay = revenue_amount;

        revenue_amount = 0;

        revenue.transfer(toPay);

        emit RevenueWithdrawal(toPay);
    }

    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol#L15-L35

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}