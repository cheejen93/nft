pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.0/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.0/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.0/contracts/utils/structs/EnumerableSet.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.0/contracts/security/ReentrancyGuard.sol";


contract NFTSalon is ERC721Enumerable, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    uint totalBalance  = 0;
    string public metaUrl;
    uint256 public percentageCut;

    constructor(uint _percentageCut,string memory _metaurl) ERC721("SuperAsset", "SUPERASSET") {
        percentageCut = _percentageCut;
        metaUrl = _metaurl;
    }

    function setPercentCut(uint _percent) public onlyOwner {
        percentageCut = _percent;
    }

    function setMetaUrl(string memory _url) public onlyOwner {
        metaUrl = _url;
    }

    //Batch Start
    uint256 public tokenBatchIndex; //Batch ID
    mapping(uint256 => string) public tokenBatchHash; // Key -> Batch ID  : Value -> File Hash
    mapping(uint256 => string) public tokenBatchName; // Key -> Batch ID  : Value -> Batch Title
    mapping(uint256 => uint256) public tokenBatchEditionSize; // Key -> Batch ID  : Value -> how many tokens can we mint in the same batch (group)
    mapping(uint256 => uint256) public totalMintedTokens; // Key -> Batch ID  : Value -> ERC721 tokens already minted under same batch
    mapping(uint256 => address) public tokenCreator; // Key -> Batch ID : value -> address of creator
    mapping(uint256 => string) public fileUrl; // Key -> Batch ID : value -> fileUrl
    mapping(uint256 => string) public thumbnail; // Key -> Batch ID : value -> thumbnail url
    mapping(uint256 => address payable [5]) public royaltyAddressMemory; // Key -> Batch ID  : Value -> creator (artist) address
    mapping(uint256 => uint256[5]) public royaltyPercentageMemory;  // Key -> Batch ID  : Value -> percentage cut  for artist and owner
    mapping(uint256 => uint256) public royaltyLengthMemory; // Key -> Batch ID  : Value -> Number of royalty parties (ex. artist1, artist2)
    mapping(uint256 => bool) public openMinting; // Key -> Batch ID  : Value -> minting open or not
    mapping(uint256 => uint256) tokenBatchPrice; // Key -> Batch ID  : Value -> price of Batch
    mapping(uint256 => bool) public isSoldorBidded; // Key -> Batch ID  : Value -> bool (has any token of that batch been sold or auctioned)
    //Batch end
    
    mapping(address => EnumerableSet.UintSet) internal tokensOwnedByWallet;
    mapping(address => uint256) internal userBalance;
    mapping(uint256 => bool) public isSellings;
    mapping(uint256 => uint256) public sellPrices;
    mapping(uint256 => uint256) public tokenEditionNumber;
    mapping(uint256 => uint256) public referenceTotokenBatch; //name : tokenIdToBatchId // Key -> Token ID  : Value -> Batch Id to which it belongs to
    mapping(uint256 => Auction) public auctions;
    //Token end
    //Auction structure
    struct Auction {
        address payable bidder;
        uint bidPrice;  
        bool isBidding;
        uint bidEnd;
        address seller;
        bool isCountdown;
    }
    
    //Event
    event newTokenBatchCreated(string tokenHash, string tokenBatchName, uint256 editionSize, uint256 price, uint256 tokenBatchIndex, address creator, uint timestamp);
    event tokenCreated(uint indexed tokenId, address indexed tokenCreator, uint timestamp, uint indexed batchId);
    event tokenPutForSale(uint indexed tokenId, address indexed seller, uint sellPrice, bool isListed, uint timestamp);
    event tokenBid(uint indexed tokenId, address indexed bidder, uint tokenPrice, uint timestamp);
    event bidStarted(uint indexed tokenId, address indexed lister, bool isBid, uint tokenPrice, uint endTime, bool isClosedBySuperWorld, uint timestamp);
    event tokenBought(uint indexed tokenId, address indexed newowner, address indexed seller, uint timestamp, uint tokenPrice);
    //Event
    
    //only the owner of token allowed
    modifier ownerToken(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender,"Not TokenOwner");
        _;
    }
    
    //only the creator of token allowed
    modifier creatorToken(uint256 tokenBatchId) {
        require(tokenCreator[tokenBatchId] == msg.sender,"Not tokenCreator");
        _;
    }
    
    // **
    // Use : Creates a token batch
    // Input : file hash, batch name, edition size, price, fileURL and thumbnailUrl
    // Output : New token batch with file hash, name, size, price, fileURL and thumbnailUrl
    function createTokenBatch(string memory _tokenHash,  string memory _tokenBatchName,  uint256 _editionSize, uint256 _price, string memory _fileUrl, string memory _fileThumbnail) public returns(uint256) {
        tokenBatchIndex++;
        tokenBatchHash[tokenBatchIndex] = _tokenHash;
        tokenBatchName[tokenBatchIndex] = _tokenBatchName;
        tokenBatchEditionSize[tokenBatchIndex] = _editionSize;
        totalMintedTokens[tokenBatchIndex] = 0;
        tokenBatchPrice[tokenBatchIndex] = _price;
        fileUrl[tokenBatchIndex] = _fileUrl;
        thumbnail[tokenBatchIndex] = _fileThumbnail;
        tokenCreator[tokenBatchIndex] = msg.sender;
        emit newTokenBatchCreated(_tokenHash, _tokenBatchName, _editionSize, _price, tokenBatchIndex, msg.sender, block.timestamp);
        return tokenBatchIndex;
    }

    // Used for Opening/Closing a minting session where buyers can pay and mint stuffs directly at a price set by creator
    // Input : toke price, bool (True Opening minting session/False = Closing minting session)
    // Output : Minting status
    function openCloseMint(uint256 tokenBatchToUpdate, uint256 _price, bool _isOpen) public creatorToken(tokenBatchToUpdate) {
        openMinting[tokenBatchToUpdate] = _isOpen;
        tokenBatchPrice[tokenBatchToUpdate] = _price;
    }

    // Use : Adds up to five addresses to recieve royalty percentages
    // Input : Token Batch Id, array of adresses, array of percentages
    // Output :  Added royalties and their percentages
    function addTokenBatchRoyalties(uint256 tokenBatchId, address[] memory _royaltyAddresses, uint256[] memory _royaltyPercentage) public creatorToken(tokenBatchId){
        require(_royaltyAddresses.length == _royaltyPercentage.length,"royaltyAddress not match royaltyPercentage length");
        require(_royaltyAddresses.length <= 5,"Maximum size exceeded");
        require(isSoldorBidded[tokenBatchId] == false,"Token already sold or bidded");
        uint256 totalCollaboratorRoyalties;
        for(uint256 i=0; i<5; i++){
            if (i < _royaltyAddresses.length) { 
                royaltyAddressMemory[tokenBatchId][i] = payable(_royaltyAddresses[i]);
                royaltyPercentageMemory[tokenBatchId][i] = _royaltyPercentage[i];
                totalCollaboratorRoyalties += _royaltyPercentage[i];
            }
            else {
                royaltyAddressMemory[tokenBatchId][i] = payable(address(0x0));
                royaltyPercentageMemory[tokenBatchId][i] = 0;    
            }
        }
        require(totalCollaboratorRoyalties <= 100,"Max percentage reached");
        royaltyLengthMemory[tokenBatchId] = _royaltyAddresses.length;
    }

    // Use : Getter function for royalty addresses and proyalty percerntages
    // Input : Token Batch ID
    // Output : Puts royalty addresses and royalty percentages into two seperate arrays
    function getRoyalties(uint256 tokenBatchId) public view returns (address[5] memory addresses, uint256[5] memory percentages) {
        for(uint256 i=0; i<royaltyLengthMemory[tokenBatchId]; i++){
            addresses[i] = royaltyAddressMemory[tokenBatchId][i];
            percentages[i] = royaltyPercentageMemory[tokenBatchId][i];
        }
    }
    
    // Use : Minting new tokens from batch
    // Input : Token Batch ID, amount of tokens to mint
    // Output : minted token(s)
    function mintTokenBatch(uint256 tokenBatchId, uint256 amountToMint) public payable{
        for (uint i = 0 ; i<amountToMint; i++) {
            mintToken(tokenBatchId);
        }
    }
    
    // Use : Minting new tokens one at a time 
    //      1: if openminting enabled buyers mint with the price the creator has set and the pay goes to the royalty and creator
    //      2: if openminting disabled only creator can mint
    // Input : Token Batch ID
    // Output : minted token(s)
    function mintToken(uint256 tokenBatchId) public payable{
        uint safeState = totalMintedTokens[tokenBatchId] + 1;
        uint256 tokenId;
        if (openMinting[tokenBatchId]) {
            require(tokenBatchPrice[tokenBatchId] <= msg.value,"Less Value sent");
            require(safeState <= tokenBatchEditionSize[tokenBatchId],"Max Batch capacity exceeded");   
            tokenId = totalSupply() + 1;
            _safeMint(msg.sender, tokenId);
            uint256 totalMoney = msg.value;             //100 Ethers
            address payable royaltyPerson;
            uint256 royaltyPercent;
            uint256 x;
            uint fee = 
                (msg.value * percentageCut)/100;   //15 percentageCut fee = 15 ETH 
            totalMoney = totalMoney - fee;         //totalMoney = 85
            totalBalance += fee;                            
        
            uint priceAfterFee = totalMoney;                    //priceAfterFee = 85
            for (uint256 i=0; i<royaltyLengthMemory[tokenBatchId]; i++) {   // 20 30 10 15 25 = 100
                royaltyPerson = royaltyAddressMemory[tokenBatchId][i];
                royaltyPercent = royaltyPercentageMemory[tokenBatchId][i];
                x = (priceAfterFee*royaltyPercent)/100; 
                totalMoney = totalMoney - x;
               //royaltyPerson.transfer(x);
                (bool success, ) = royaltyPerson.call{value: x}("");
                //17 25.5 10 12.75 21.25
            }
            if (totalMoney > 0) {
               // (payable(tokenCreator[tokenBatchId])).transfer(totalMoney);
                (bool success, ) = (tokenCreator[tokenBatchId]).call{value: totalMoney}("");
            }
            referenceTotokenBatch[tokenId] = tokenBatchId;
            totalMintedTokens[tokenBatchId]++;
            tokenEditionNumber[tokenId] = totalMintedTokens[tokenBatchId];
            tokensOwnedByWallet[msg.sender].add(tokenId);
        }
        else {
            require(tokenCreator[tokenBatchId] == msg.sender,"Not tokenCreator");
            require(safeState <= tokenBatchEditionSize[tokenBatchId],"Max Batch capacity exceeded");
            tokenId = totalSupply() + 1;
            _safeMint(msg.sender, tokenId);
            referenceTotokenBatch[tokenId] = tokenBatchId;
            totalMintedTokens[tokenBatchId]++;
            tokenEditionNumber[tokenId] = totalMintedTokens[tokenBatchId];
            tokensOwnedByWallet[msg.sender].add(tokenId);
        }
        emit tokenCreated(tokenId, msg.sender, block.timestamp, tokenBatchId);
    }

    // Use : List token for sell (If you want to resell you re-list or de-list also)
    // Input : Token ID, selling price, is listed should be true
    // Output : Token ID, sellprice, if it is listed, timestamp
    function sale(uint256 _tokenId, uint _sellPrice, bool isListed) public ownerToken(_tokenId) { 
        require(auctions[_tokenId].isBidding == false,"Token on bidding");
        isSellings[_tokenId] = isListed;
        sellPrices[_tokenId] = _sellPrice;
        emit tokenPutForSale(_tokenId, msg.sender, _sellPrice, isListed, block.timestamp);
    }

    function bulkSale(uint256[] memory _tokens, uint _sellPrice, bool _isListed) public { //moresale casing //change name
        for (uint i=0; i<_tokens.length; i++) {
            sale(_tokens[i], _sellPrice, _isListed);
        }
    }

    // **
    // Use : Gets all information about the batch from the Token Batch ID
    // Input : Token Batch ID
    // Output : Token hash, token batch name, token batch edition size, token creator, and image URL
    function getTokenBatchData(uint256 tokenBatchId) public view returns (uint256 _batchId, string memory _tokenHash, string memory _tokenBatchName, uint256 _unmintedEditions, address _tokenCreator, string memory _fileUrl, string memory _fileThumbnail, uint256 _mintedEditions, bool _openMinting, bool _isSoldorBidded, uint _tokenBatchPrice) {
        _batchId = tokenBatchId;
        _tokenHash = tokenBatchHash[tokenBatchId];
        _tokenBatchName = tokenBatchName[tokenBatchId];
        _unmintedEditions = tokenBatchEditionSize[tokenBatchId] - totalMintedTokens[tokenBatchId];
        _mintedEditions = totalMintedTokens[tokenBatchId];
        _tokenCreator = tokenCreator[tokenBatchId];
        _fileUrl = fileUrl[tokenBatchId];
        _fileThumbnail = thumbnail[tokenBatchId];  
        _openMinting = openMinting[tokenBatchId];
        _isSoldorBidded = isSoldorBidded[tokenBatchId];
        _tokenBatchPrice = tokenBatchPrice[tokenBatchId];
    }


    // Use : Gets all information about a token from the Token ID
    // Input : Token id
    // Output : Token hash, token batch name, token batch edition size, token creator, and image URL Token owner, if it is currently for sale, sell price, referefence to its token batch, auctions, token bidder, if it is bidding, and bid price
    function getTokenData(uint256 tokenId) public view returns (string memory _tokenHash, string memory _tokenBatchName, address _tokenCreator, string memory _fileUrl, string memory _fileThumbnail, address _tokenOwner, bool _isSellings, uint _sellPrices, uint _refBatch, Auction memory _aucObj, uint _tokenId, uint _editionNo) {
        require(_exists(tokenId), "Not exist");
        _refBatch = referenceTotokenBatch[tokenId];
        _tokenHash = tokenBatchHash[_refBatch];
        _tokenBatchName = tokenBatchName[_refBatch];
        _tokenCreator = tokenCreator[_refBatch];
        _fileUrl = fileUrl[_refBatch];
        _fileThumbnail = thumbnail[_refBatch];
        _tokenOwner = ownerOf(tokenId);
        _isSellings = isSellings[tokenId];
        _sellPrices = sellPrices[tokenId];
        _aucObj = auctions[tokenId];
        _tokenId = tokenId;
        _editionNo = tokenEditionNumber[tokenId];

    }

    // Use : Start a bid
    // Input : Token ID, start price, endtime of auction and type of auction 
    //{isCountdown = true => auction starts for input time starting from first bid for endtime no. of days. if false auction ends on a end date}
    // Output : Emit bidStarted event by giving token ID, address, setting event to true, false(represents the creator), and time stamp
    function startBid(uint _tokenId, uint256 _startPrice, uint _endTimestamp, bool _isCountdown) public ownerToken(_tokenId){
        require(isSellings[_tokenId] == false,"Token on sale");                       //check if its not on sale
        require(auctions[_tokenId].isBidding == false, "Token already on auction");   //check if its not on auction
        if (_isCountdown == false) {
            require(_endTimestamp > block.timestamp,"Extend EndTime");                    //Endtime should not be in past
            require(_endTimestamp < (block.timestamp + 31 days),"Reduce the end time");    //Cannot put auction for more than 1 month
        }
        else{
            require(_endTimestamp < 31 days,"Reduce the end days");
        }
        auctions[_tokenId].isCountdown = _isCountdown;
        auctions[_tokenId].bidEnd = _endTimestamp;
        auctions[_tokenId].isBidding = true; 
        auctions[_tokenId].bidPrice = _startPrice;
        auctions[_tokenId].seller = msg.sender;
        emit bidStarted(_tokenId, msg.sender, true, _startPrice, _endTimestamp, false, block.timestamp);
    }

    // Use : Add a bid to auction
    // Input : Token ID
    // Output : Emit tokenBid event by giving token id, bidder adress, bid ammount, and timestamp of event
    function addBid(uint _tokenId) public payable{
        require(auctions[_tokenId].isBidding,"Auction ended");              
        require(msg.value > auctions[_tokenId].bidPrice,"Increase Bid");         //Bidprice lower than what was before
        if (auctions[_tokenId].bidder == payable(address(0x0))) {
            if (auctions[_tokenId].isCountdown == false) {
               require(auctions[_tokenId].bidEnd > block.timestamp,"Auction ended"); 
            }    
            else {
                auctions[_tokenId].bidEnd += block.timestamp;                    //start the countdown timer to end the bid
            }
            auctions[_tokenId].bidder = payable(msg.sender);
            auctions[_tokenId].bidPrice = msg.value;
            auctions[_tokenId].isBidding = true;
            emit tokenBid(_tokenId, msg.sender, msg.value, block.timestamp);
        }
        else{
            require(auctions[_tokenId].bidEnd > block.timestamp,"Auction ended");
            (bool success, ) = (auctions[_tokenId].bidder).call{value: auctions[_tokenId].bidPrice}("");
            if(success == false){
                userBalance[auctions[_tokenId].bidder] += auctions[_tokenId].bidPrice;
            }
            auctions[_tokenId].bidder = payable(msg.sender);
            auctions[_tokenId].bidPrice = msg.value;
            emit tokenBid(_tokenId, msg.sender, msg.value, block.timestamp);
        }
    }

    // Use : Allows contract owner to close a bid and give back the money to the bidder and token will be set not for auction anymore
    //Pull pattern used if the transfer to the bidder was not possible ... they can use withdrawUserBalance
    // Input : Token ID
    // Output : Emit bidStarted event by giving token ID, address, sets bidding to false, true(represents SuperWorld) and, timestamp
    function closeBid(uint _tokenId) public onlyOwner{
        require(auctions[_tokenId].bidEnd < block.timestamp,"Active Auction");
        //auctions[_tokenId].bidder.transfer(auctions[_tokenId].bidPrice);  
        (bool success, ) = (auctions[_tokenId].bidder).call{value: auctions[_tokenId].bidPrice}("");
        if(success == false){
            userBalance[auctions[_tokenId].bidder] += auctions[_tokenId].bidPrice;
        }
        auctions[_tokenId].bidder = payable(address(0x0));
        auctions[_tokenId].bidPrice = 0;
        auctions[_tokenId].isBidding = false;
        auctions[_tokenId].seller = address(0x0);
        emit bidStarted(_tokenId, msg.sender, false, 0, 0, true, block.timestamp);
    }

    // Use : Getter function for token URL
    // Input : Token Id
    // Output : String URL
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(metaUrl, toString(tokenId)));
    }
    
    //Use : openseas transaction .. we need to emit events from our end to match with our events
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
        isSoldorBidded[referenceTotokenBatch[tokenId]] = true;
        uint price;
        if(isSellings[tokenId] == true) {
           isSellings[tokenId] = false;
           price = sellPrices[tokenId];
           sellPrices[tokenId] = 0;
           emit tokenPutForSale(tokenId, from, 0, false, block.timestamp);
        }
        else if(auctions[tokenId].isBidding == true) {
            if (auctions[tokenId].bidder == payable(address(0x0))) {
               price = auctions[tokenId].bidPrice;
               auctions[tokenId].isBidding = false;
               auctions[tokenId].bidPrice = 0;
               auctions[tokenId].seller = address(0x0);
               auctions[tokenId].bidEnd = 0;
               auctions[tokenId].isCountdown = false;
               emit bidStarted(tokenId, from, false, 0, 0, false, block.timestamp);
            }
            else if (auctions[tokenId].bidder != payable(address(0x0))) {
                if (auctions[tokenId].bidder != to) {
                    (bool success, ) = (auctions[tokenId].bidder).call{value: auctions[tokenId].bidPrice}("");
                    if (success == false) {
                        userBalance[auctions[tokenId].bidder] += auctions[tokenId].bidPrice;
                    }
                }
                price = auctions[tokenId].bidPrice;
                auctions[tokenId].bidder = payable(address(0x0));
                auctions[tokenId].bidPrice = 0;
                auctions[tokenId].isBidding = false;
                auctions[tokenId].seller = address(0x0);
                auctions[tokenId].bidEnd = 0;
                auctions[tokenId].isCountdown = false;
                emit bidStarted(tokenId, from, false, 0, 0, true, block.timestamp); 
            }
        }
        emit tokenBought(tokenId, from, to, block.timestamp,price);
        tokensOwnedByWallet[from].remove(tokenId);
        tokensOwnedByWallet[to].add(tokenId);
    }
    
    // Use : Buy a token
    // Input : Token ID
    // Output : Calls _buyToken event by giving Token ID, address, buy amount, and 1(represents buy function)
    function buyToken(uint256 _tokenId) public payable returns(bool) {
        require(isSellings[_tokenId],"Token not selling");
        require(msg.value >= sellPrices[_tokenId],"Add more value");
        return _buyToken(_tokenId, payable(msg.sender), msg.value, 1);
    }

    // Use : Buy a token
    // Input : Token ID, address that will be paid, cost amount, and 1(represents called by selling) or 2 (called while in auction)
    // Output : Boolean
    function _buyToken(uint256 _tokenId, address payable buyer, uint256 _price, uint8 _type) private returns(bool) {
        uint256 totalMoney = _price;             //100 Ethers
        address payable royaltyPerson;
        uint256 royaltyPercent;
        uint256 x;
        isSoldorBidded[referenceTotokenBatch[_tokenId]] = true;
        uint fee = (_price * percentageCut)/100;   //15 percentageCut fee = 15 ETH 
        totalMoney =totalMoney - fee;         //totalMoney = 85
        totalBalance += fee;                            
        uint256 batchId = referenceTotokenBatch[_tokenId];
        uint priceAfterFee = totalMoney;                    //priceAfterFee = 85
        for (uint256 i=0; i<royaltyLengthMemory[batchId]; i++) {   // 20 30 10 15 25 = 100
            royaltyPerson = royaltyAddressMemory[batchId][i];
            royaltyPercent = royaltyPercentageMemory[batchId][i];        // 10
            x = (priceAfterFee * royaltyPercent)/100;                     //8.5
            totalMoney = totalMoney - x;
           // royaltyPerson.transfer(x);    //17 25.5 10 12.75 21.25 = 85
            (bool success, ) = (royaltyPerson).call{value: x}("");
        }
        address payable seller = payable(ownerOf(_tokenId));        //totalMoney = 0
        if (totalMoney > 0) {
            //seller.transfer(totalMoney);    
            (bool success, ) = (seller).call{value: totalMoney}("");
        }
        _transfer(seller, buyer, _tokenId);
        return true;
    }

    // Use : Close bid by owner of the token only.... the token sent to the highest bidder(if any) otherwise removed from being in auction
    // Input : Token ID
    // Output : Calls _buytoken function by giving Token ID, bidder,bid price, and 2(triggers a two in _buytoken function)
    function closeBidOwner(uint _tokenId) public ownerToken(_tokenId) returns(bool) {
        if (auctions[_tokenId].bidder == payable(address(0x0))) {
            auctions[_tokenId].bidEnd = 0;
            auctions[_tokenId].isBidding = false;
            auctions[_tokenId].bidPrice = 0;
            auctions[_tokenId].seller = address(0x0);
            auctions[_tokenId].isCountdown = false;
            address _tokenOwner = ownerOf(_tokenId);
            emit bidStarted(_tokenId, _tokenOwner, false, 0, 0, false, block.timestamp);
            return true;
        }
        else {
            require(auctions[_tokenId].seller == ownerOf(_tokenId),"Starter of bid not owner");
            require(auctions[_tokenId].bidEnd < block.timestamp,"Active Auction");
            require(auctions[_tokenId].isBidding,"Token not bidding");
            return _buyToken(_tokenId, auctions[_tokenId].bidder, auctions[_tokenId].bidPrice, 2);
        }
    }
    // Use : Close bid by bidder if the seller doen't close bid 
    //1. someone bought it on openseas -> bidder gets back money  2. owned by Starter of bid -> bidder gets token and prev owner gets money
    // Input : Token ID
    // Output : Calls _buytoken function by giving Token ID, bidder,bid price, and 2(triggers a two in _buytoken function)
    function closeBidBuyer(uint _tokenId) public returns(bool) {
        require(auctions[_tokenId].bidEnd < block.timestamp,"Active Auction");
        require(auctions[_tokenId].bidder == msg.sender,"Not Bidder");
        require(auctions[_tokenId].isBidding,"Not on bidding");
        return _buyToken(_tokenId, auctions[_tokenId].bidder, auctions[_tokenId].bidPrice, 2);
    }
    
    // Use : Get Owned NFTs from wallet address
    function getOwnedNFTs(address _owner) public view returns(string memory) {
        uint len = EnumerableSet.length(tokensOwnedByWallet[_owner]);
        string memory intString;
       
        for(uint j = 0; j<len; j++) {
            if (j > 0) {
                intString = string(abi.encodePacked(intString, ",", toString((EnumerableSet.at(tokensOwnedByWallet[_owner], j)))));
            }
            else {
                intString = string(abi.encodePacked(toString((EnumerableSet.at(tokensOwnedByWallet[_owner], j)))));
            }
         }
        return intString; 
    }
    
    // Use : Withdraw funds from smart contract owned by SW
    // Input : None
    // Output : Transfer iniated
    function withdrawBalance() public payable onlyOwner() nonReentrant() {
        require(totalBalance > 0,"Not enough funds");
        (bool success , ) = msg.sender.call{value: totalBalance}("");
        if(success){
            totalBalance = 0;
        }
        //(payable(msg.sender)).transfer(totalBalance);
    }
    // Use : Withdraw funds from smart contract owned by the user(if any)
    // Input : None
    // Output : Transfer iniated
    
    function withdrawUserBalance() public payable nonReentrant() {
        require(userBalance[msg.sender] > 0,"Not enough funds");
        (bool success, ) = msg.sender.call{value: userBalance[msg.sender]}("");
        if(success){
            userBalance[msg.sender]  = 0;
        }
        require(!success,"Transfer failed");
        //(payable(msg.sender)).transfer(totalBalance);
    }

    // Use : Converts an integer to a string
    // Input : Integer
    // Output : String

    function toString(uint256 _i)internal pure returns (string memory str){
        if (_i == 0){
            return "0";
           }
        uint256 j = _i;
        uint256 length;
        while (j != 0){
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0)
        {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
    
    // Use : Converts an address to a string
    // Input : Address
    // Output : String
    
    function toString(address _i) internal pure returns (string memory str){
        str = toString(uint(uint160(_i)));
    }
    
    
    // Use : Converts an bool to a string
    // Input : Bool
    // Output : String

    function toString(bool _i) internal pure returns (string memory str){
        str = _i == true ? "true" : "false";
         
    }
}
