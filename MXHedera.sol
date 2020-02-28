pragma solidity >=0.4.25;
import "./AddressUtils.sol";

//Last updated by Zol, 2020.02.28
contract ERC20Interface {
    function allowance(address _from, address _to) public view returns(uint);
    function transferFrom(address _from, address _to, uint _sum) public;
    function transfer(address _to, uint _sum) public;
    function balanceOf(address _owner) public view returns(uint);
}

contract MXHedera {
    
    event Transfer(address indexed _from, address indexed _to, uint _sum);
    event OuterOrderCreated(address indexed _buyer, uint indexed _orderId, uint _amount);
    event OrderPaid(address indexed _buyer, uint indexed _orderId);
    event TokenBought(address indexed _buyer, uint indexed _promoter, uint _sum);
    event TokenBoughtFromSeller(address indexed _buyer, address _seller, uint _amount, uint indexed _offerId);
    event SetToSale(address indexed _seller, uint indexed _offerId, uint _amount, uint _unitPrice);
    event ApproveTransfer(address indexed _seller, address indexed _buyer, uint _amount);
    event TxApproval(address indexed _from, address indexed _to, uint _sum, uint _id);
    
    using AddressUtils for address;
    uint public initSupply;
    address public spotMarketAddress;
    address public depositAddress;
    uint supply;
    uint decimals;
    mapping(address => uint) public balanceOf;
    mapping(address => uint) public orderByAddress;
    mapping(uint => address) public orderById;
    mapping(uint => bool) public orderPaid;
    uint[] public orderAmountById;
    uint orderId = 0;
    
    mapping(address => uint) public saleOffersByAddress;
    mapping(uint => address) public saleOffersById;
    uint public saleOffersCounter = 0;
    mapping(uint => uint) public saleOffersAmount;
    mapping(uint => uint) public saleOffersUnitPrice;
    
    mapping(uint => uint) buyBackOfferByPrice;
    struct BuyBackOffer {
        uint price;
        uint amount;
    }
    BuyBackOffer[] buyBackOffers;
    uint public buyBackOfferCounter = 0;
    uint public hbarsToBuyBack = 0;
    
    mapping(address => mapping(address => uint)) public approvedTransfers;
    
    string public name;
    string public symbol;
    //address public contractOwner;
    address public operatorOfContract;
    
    address[] serverAddress;
    uint serverAddressArrayLength;
    mapping(address => bool) isOurServer;
    
    uint public priceUSD; //0.01 USD cent
    uint public priceHbar; 
    uint public HbarUSDprice;
    uint public lastDailyLimitUpdate;
    uint public dailyBasePrice; // 0.01 USD cent
    uint public dailyUpperBound;
    uint public dailyLowerBound;

    modifier onlyServer() {
        require(isOurServer[msg.sender]);
        _;
    }
    
    modifier operator() {
        require(msg.sender == operatorOfContract);
        _;
    }
    
   struct ToTransfer {
       address tokenFrom;
       address tokenTo;
       uint tokenAmount;
    }
    
    ToTransfer[] toTransfers;
    uint public toTransferCounter = 0;
    
    constructor (address _operator, uint _initSupply, string memory _name, string memory _symbol, address _serverAddress, uint _initPriceUSD, uint _initPriceHbar) public {
        operatorOfContract = _operator;        
        balanceOf[this] = _initSupply;
        initSupply = _initSupply;
        supply = initSupply;
        name = _name;
        symbol = _symbol;
        serverAddressArrayLength = serverAddress.push(_serverAddress);
        isOurServer[_serverAddress] = true;
        //spotMarketAddress = _spotMarket;
        //depositAddress = _deposit;
        priceUSD = _initPriceUSD;
        priceHbar = _initPriceHbar; //Input in tinybar
        HbarUSDprice = priceUSD * 100000000 / priceHbar;
        lastDailyLimitUpdate = now;
        dailyBasePrice = priceUSD;
        dailyUpperBound = priceUSD * 102 / 100;
        dailyLowerBound = priceUSD * 98 / 100;
    }
    
    function totalSupply() public view returns(uint) {
        return(supply);
    }
    
    function mintByTx(uint _txAmount) private {
        uint supplyIncrease = uint(_txAmount * 2 / 100);
        supply += supplyIncrease;
        balanceOf[this] += supplyIncrease;
        //Don't add to contract's balance, but half of them to deposit, half of them to spot market
        //uint supplyIncreaseHalf = uint(_txAmount / 100);
        //balanceOf[address(spotMarketAddress)] += supplyIncrease;
        //balanceOf[address(depositAddress)] += supplyIncrease;
        //uint supplyIncrease = supplyIncreaseHalf * 2;
        //supply += supplyIncrease;
    }
    
    function mintAtUpperBound(uint _txAmount) private {
        /*
        uint upperBound = dailyBasePrice * 102 / 100;
        require(priceUSD >= upperBound);
        */
        supply += _txAmount;
        balanceOf[this] += _txAmount;
    }
    /*
    address public futuresContractAddress; Should define at constructor
    ERC20Interface futureCon = ERC20Interface(futuresContractAddress); This should have probably custom interface
    function issueOptionByCredit(uint _loanAmount, uint _interestRate) private {
        if(_interestRate > 2) {
            uint optionIncrease = uint((_loanAmount * (_interestRate - 2)) / 100);
            futureCon.supply += optionIncrease; ??? use function like futureCon.increase(optionIncrease)
            futureCon.optionBalance[address(futuresContractAddress)] += optionIncrease; ???
        }
    } */

    //MXoptions and MXfutures can be changed to MX from futuresAddress's balance
    //address public futuresAddress; should define in constructor
    function mintByRedeem(uint _loanAmount, uint _interestRate) private {
        if(_interestRate > 2) {
            uint supplyIncrease = uint((_loanAmount * (_interestRate - 2)) / 100);
            supply += supplyIncrease;
            balanceOf[this] += supplyIncrease;  
            //balanceOf[address(futuresAddress)] += supplyIncrease;
        }
    }
    
    function withdrawERC20(address _erc20Address, address _to, uint _amount) public operator {
        require(_erc20Address != address(0) && _to != address(0));
        ERC20Interface ei = ERC20Interface(_erc20Address);
        ei.transfer(_to, _amount);
    }
    
    function withdrawHbar(address _to, uint _amount) public operator {
        require(_to != address(0));
        _to.transfer(_amount);
    }
    
    function setServerAddress(address _serverAddress) public operator {
        serverAddressArrayLength = serverAddress.push(_serverAddress);
        isOurServer[_serverAddress] = true;
    }
    
    function getServerAddressLength() public view operator returns(uint) {
        return serverAddressArrayLength;
    }
    
    function getServerAddress(uint _num) public view operator returns(address) {
        return serverAddress[_num];
    }
    
    function _transfer(address _from, address _to, uint _sum) private {
        require(_from != address(0));
        require(_to != address(0));
        require(_from != _to);
        require(_sum > 0);
        require(balanceOf[_from] >= _sum);
        require(balanceOf[_to] + _sum >= _sum);
        uint sumBalanceBeforeTx = balanceOf[_from] + balanceOf[_to]; 
        balanceOf[_from] -= _sum;
        balanceOf[_to] += _sum;
        assert(sumBalanceBeforeTx == balanceOf[_from] + balanceOf[_to]);
        mintByTx(_sum);
        emit Transfer(_from, _to, _sum);
    }
    
    function transfer(address _to, uint _sum) public {
        _transfer(msg.sender, _to, _sum);
    }
    
    //Using function overload
    function transfer(address _to, uint _sum, uint _interestRate, bool _isRedeem) public {
        require(_isRedeem);
        _transfer(msg.sender, _to, _sum);
        mintByRedeem(_sum, _interestRate); 
    }
    /*
    function transferLoan(address _to, uint _sum, uint _interestRate) public {
        _transfer(msg.sender, _to, _sum);
        mintByCredit(_sum, _interestRate);
    }
    */
    //For using other currencies like BTC, fiat...
    function createOuterOrder(uint _amount) public {
        require(_amount > 0);
        orderAmountById.push(_amount);
        orderByAddress[msg.sender] = orderId;
        orderById[orderId] = msg.sender;
        emit OuterOrderCreated(msg.sender, orderId, _amount);
        orderId ++;
    }
        /*
    function setOuterOrderPaid(uint _orderId, uint _paidAmount) public onlyServer {
        uint orderSum = orderAmountById[_orderId] * priceUSD;
        require(orderSum == _paidAmount);
        orderPaid[_orderId] = true;
        address buyerAddress = orderById[_orderId];
        emit OrderPaid(buyerAddress, _orderId);
    }
    
    function outerTransfer(uint _orderId) public {
        require(orderPaid[_orderId] == true);
        _transfer(address(this), orderById[_orderId], orderAmountById[_orderId]);
    }
        */

    function outerTransfer(uint _orderId, uint _paidAmount) public onlyServer {
        uint orderSum = orderAmountById[_orderId] * priceUSD;
        require(orderSum == _paidAmount);
        orderPaid[_orderId] = true;
        address buyerAddress = orderById[_orderId];
        emit OrderPaid(buyerAddress, _orderId);
        _transfer(address(this), orderById[_orderId], orderAmountById[_orderId]);
    }
    

    
    //----------
    
    function buyToken(uint _sum, uint _promoter) public payable {
        uint price = _sum * priceHbar;
        require(msg.value == price);
        _transfer(address(this), msg.sender, _sum);
        emit TokenBought(msg.sender, _promoter, _sum);
    }
    
    function getTokenBalance(address _owner) public view returns(uint) {
        return(balanceOf[_owner]);
    }
    
    function setToSale(uint _amount, uint _unitPrice) public {
        require(balanceOf[msg.sender] >= _amount);
        require(_unitPrice > 0);
        saleOffersByAddress[msg.sender] = saleOffersCounter;
        saleOffersById[saleOffersCounter] = msg.sender;
        saleOffersAmount[saleOffersCounter] = _amount;
        saleOffersUnitPrice[saleOffersCounter] = _unitPrice; //price in tinybar
        emit SetToSale(msg.sender, saleOffersCounter, _amount, _unitPrice);
        saleOffersCounter ++;
    }
    
    function buyFromSeller(uint _amount, uint _offerId) public payable {
        require(saleOffersAmount[_offerId] >= _amount);
        uint orderPrice = _amount * saleOffersUnitPrice[_offerId];
        require(msg.value == orderPrice);
        saleOffersAmount[_offerId] -= _amount;
        _transfer(saleOffersById[_offerId], msg.sender, _amount);
        uint sellersShare = orderPrice * 99 / 100;
        uint toSend = sellersShare;
        sellersShare = 0;
        address to = saleOffersById[_offerId];
        to.transfer(toSend);
        priceHbar = saleOffersUnitPrice[_offerId];
        priceUSD = priceHbar / HbarUSDprice;
        emit TokenBoughtFromSeller(msg.sender, saleOffersById[_offerId], _amount, _offerId);
        if(priceUSD >= dailyUpperBound) {
            mintAtUpperBound(_amount);
        }
    }
    
    function approveTx(address _to, uint _sum) public {
        toTransfers.push(ToTransfer(msg.sender, _to, _sum));
        emit TxApproval(msg.sender, _to, _sum, toTransferCounter);
        toTransferCounter ++;
    }
    
    function getApprovedTx(uint _id) public view returns(address, address, uint) {
        return(toTransfers[_id].tokenFrom, toTransfers[_id].tokenTo, toTransfers[_id].tokenAmount);
    }
    
    function transferById(uint _transferId) public {
        _transfer(toTransfers[_transferId].tokenFrom, toTransfers[_transferId].tokenTo, toTransfers[_transferId].tokenAmount);
        toTransfers[_transferId].tokenAmount = 0;
    }
    
    function transferByIdPartly(uint _transferId, uint _amount) public {
        require(toTransfers[_transferId].tokenAmount >= _amount);
        _transfer(toTransfers[_transferId].tokenFrom, toTransfers[_transferId].tokenTo, _amount);
        toTransfers[_transferId].tokenAmount -= _amount;
    }
    
    
    function approve(address _spender, uint _sum) public {
        approvedTransfers[msg.sender][_spender] += _sum;
        emit ApproveTransfer(msg.sender, _spender, _sum);
    }
    
    function allowance(address _from, address _to) public view returns(uint) {
        return (approvedTransfers[_from][_to]);
    }
    
    function transferFrom(address _from, address _to, uint _sum) public {
        require(approvedTransfers[_from][msg.sender] >= _sum);
        approvedTransfers[_from][msg.sender] -= _sum;
        _transfer(_from, _to, _sum);
    }
    
    //Using function overload
    function transferFrom(address _from, address _to, uint _sum, uint _interestRate, bool _isRedeem) public {
        require(_isRedeem);
        require(approvedTransfers[_from][msg.sender] >= _sum);
        approvedTransfers[_from][msg.sender] -= _sum;
        _transfer(_from, _to, _sum);
        mintByRedeem(_sum, _interestRate); 
    }
    
    //_priceHbar in tinybar, _priceUSD and _HbarUSDprice in 0.01 USD cent
    function setPrice(uint _priceUSD, uint _priceHbar, uint _HbarUSDprice) public onlyServer() {
       priceUSD = _priceUSD;
       priceHbar = _priceHbar; 
       HbarUSDprice = _HbarUSDprice;
    }
    
    //DailyBasePrice is calculated in USD
    function setDailyBasePrice(uint _price) public onlyServer() {
        require(now > lastDailyLimitUpdate + 86400);
        uint lastBasePrice = dailyBasePrice;
        dailyUpperBound = lastBasePrice * 102 / 100;
        dailyLowerBound = lastBasePrice * 98 / 100;
        
        if(_price <= dailyUpperBound && _price >= dailyLowerBound) {
            dailyBasePrice = _price;
        } else if (_price > dailyUpperBound) {
            dailyBasePrice = dailyUpperBound;
        } else {
            dailyBasePrice = dailyLowerBound;
        }
    }
    
    //_priceHbar in tinybar, _priceUSD and _HbarUSDprice in 0.01 USD cent
    function checkPrice(uint _priceUSD, uint _priceHbar, uint _HbarUSDprice, uint _txAmount) public onlyServer() {
        uint USDpriceFromHbar = _priceHbar * _HbarUSDprice / 100000000;
        if(_priceUSD >= dailyUpperBound || USDpriceFromHbar >= dailyUpperBound) {
            mintAtUpperBound(_txAmount);
        }
        if(_priceUSD <= dailyLowerBound || USDpriceFromHbar <= dailyLowerBound) {
            buyBackOrder(_txAmount);
        }
    }
    
    function buyBackOrder(uint _txAmount) public onlyServer() {
        if(address(this).balance > 0) {
            if(address(this).balance > hbarsToBuyBack) {
                buyBackOffers.push(BuyBackOffer(dailyLowerBound, _txAmount));
                buyBackOfferCounter++;
                hbarsToBuyBack += (_txAmount * dailyLowerBound * HbarUSDprice);
            }
        }
    }
    
    function buyBack(uint _txAmount, uint _buyBackOfferId) public payable {
        require(_txAmount <= buyBackOffers[_buyBackOfferId].amount);
        require(msg.value == buyBackOffers[_buyBackOfferId].price * _txAmount * HbarUSDprice);
        buyBackOffers[_buyBackOfferId].amount -= _txAmount;
        hbarsToBuyBack -= _txAmount * buyBackOffers[_buyBackOfferId].price * HbarUSDprice;
    }
    
    function transferFromContract(address _addr, uint _amount) public operator() {
        _transfer(address(this), _addr, _amount);
    }
    
    /*
    TestUserInterface tui = TestUserInterface(...); need TestUserInterface
    function approveToAllAddress(uint _sum, address _spender) public {
        uint addressCount = tui.userAddressCount(msg.sender); should create this function
        uint user = tui.userByAddress(msg.sender);
        for(uint i = 0; i < addressCount; i++) {
            address currentAddress = tui.getUserAddress(user, i);
            approvedTransfers[currentAddress][_spender] += _sum;
            emit ApproveTransfer(currentAddress, _spender, _sum);
        }
    }
    */
}
