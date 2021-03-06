pragma solidity >=0.4.25;
import "./AddressUtils.sol";

contract ERC20Interface {
    function allowance(address _from, address _to) public view returns(uint);
    function transferFrom(address _from, address _to, uint _sum) public;
    function transfer(address _to, uint _sum) public;
    function balanceOf(address _owner) public view returns(uint);
    function decimals() public view returns(uint8);
    function checkPrice(uint _priceUSD, uint _priceHbar, uint _HbarUSDprice, uint _txAmount) public;
}

contract MXHederaDEX {
    
    event SetOrderHbarBid(uint indexed _orderId, uint _amount, uint _price, uint _lastTo);
    event SetOrderHbarAsk(uint indexed _orderId, uint _amount, uint _price, uint _lastTo);
    event SetOrderERC20(uint indexed _orderType, uint indexed _orderId, uint _amount, uint _price, uint _lastTo, address _currencyAddress);
    event DeleteOrder(uint indexed _orderId);
    event AcceptHbarBid(uint indexed _orderId, uint _amount);
    event AcceptHbarAsk(uint indexed _orderId, uint _amount);
    event AcceptERC20Bid();
    event AcceptERC20Ask();
    
    //enum OfferType {Bid, Ask}
    //enum CurrencyType {Hbar, ERC20}
    uint Bid = 0;
    uint Ask = 1;
    uint Hbar = 0;
    uint ERC20 = 1;
    
    using AddressUtils for address;
    address public owner;
    mapping(address => mapping(uint => uint)) public ordersByAddress;
    mapping(address => uint) public orderNumberByAddress;
    address public MXAddress;
    ERC20Interface mxi;

    struct Order {
        uint orderType;
        uint orderCurrencyType;
        uint orderAmount;
        uint orderPrice;
        uint orderLastTo;
        address orderCurrencyAddress;
        address orderOwner;
        uint HbarBalance;
    }
    
    Order[] public orders;
    uint public orderCounter;
    uint orderId;
    
    constructor() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    modifier onlyOwnerOf(uint _id) {
        require(orders[_id].orderOwner == msg.sender);
        _;
    }
    
    function setMXAddress(address _addr) public onlyOwner {
        require(_addr != address(0));
        MXAddress = _addr;
        mxi = ERC20Interface(_addr);
    }
    
    function getMXallowance(address _from, address _to) public view returns(uint) {
        //return mxi.allowance(_from, _to);
        uint allow = mxi.allowance(_from, _to);
        return allow;
    }
    
    function setOrderHbarBid(uint _amount, uint _price, uint _lastTo) public payable {
        uint HbarBidPrice = _amount * _price;
        require(HbarBidPrice == msg.value); //take to setOrder
        orderId = orders.push(Order(Bid, Hbar, _amount, _price, now + _lastTo, address(0), msg.sender, HbarBidPrice)); 
        ordersByAddress[msg.sender][orderNumberByAddress[msg.sender]] = orderId;
        orderNumberByAddress[msg.sender] ++;
        orderCounter++;
        emit SetOrderHbarBid(orderId, _amount, _price, _lastTo);
    }

    function setOrderHbarAsk(uint _amount, uint _price, uint _lastTo) public {
        require(mxi.allowance(msg.sender, address(this)) >= _amount); //take to setOrder
        orderId = orders.push(Order(Ask, Hbar, _amount, _price, now + _lastTo, address(0), msg.sender, 0)); 
        ordersByAddress[msg.sender][orderNumberByAddress[msg.sender]] = orderId;
        orderNumberByAddress[msg.sender] ++;
        orderCounter++;
        emit SetOrderHbarAsk(orderId, _amount, _price, _lastTo);
    }
    
    function setOrderERC20(uint _orderType, uint _amount, uint _price, uint _lastTo, address _currencyAddress) public {
        if(_orderType == 0) {
            require(ERC20Interface(_currencyAddress).allowance(msg.sender, address(this)) >= _amount);
        }
        if(_orderType == 1) {
            require(mxi.allowance(msg.sender, address(this)) >= _amount);
        }
        orderId = orders.push(Order(_orderType, ERC20, _amount, _price, now + _lastTo, _currencyAddress, msg.sender, 0)); 
        ordersByAddress[msg.sender][orderNumberByAddress[msg.sender]] = orderId;
        orderNumberByAddress[msg.sender] ++;
        orderCounter++;
        emit SetOrderERC20(_orderType, orderId, _amount, _price, _lastTo, _currencyAddress);
    }
    
    function deleteOrder(uint _orderId) public onlyOwnerOf(_orderId) {
        address sendBack = orders[_orderId].orderOwner;
        if(orders[_orderId].HbarBalance > 0) {
            sendBack.transfer(orders[_orderId].HbarBalance);
            orders[_orderId].HbarBalance = 0;
        }
        orders[_orderId].orderAmount = 0;
        orders[_orderId].orderPrice = 0;
        orders[_orderId].orderLastTo = 0;
        orders[_orderId].orderOwner = address(0);
        orders[_orderId].orderCurrencyAddress = address(0);
        emit DeleteOrder(_orderId);
    }
    
    function acceptBidHbar(uint _orderId, uint _amount, uint _priceUSD, uint _HbarUSDprice) public {
        require((orders[_orderId].orderType) == Bid);
        require(orders[_orderId].orderCurrencyType == Hbar);
        require(orders[_orderId].orderAmount >= _amount);
        require(mxi.allowance(msg.sender, address(this)) >= _amount);
        uint bidHbarPrice = orders[_orderId].orderPrice * _amount;
        msg.sender.transfer(bidHbarPrice);
        mxi.transferFrom(msg.sender, orders[_orderId].orderOwner, _amount);
        emit AcceptHbarBid(_orderId, _amount);
        orders[_orderId].orderAmount -= _amount;
        orders[_orderId].HbarBalance -= bidHbarPrice;
        mxi.checkPrice(_priceUSD, orders[_orderId].orderPrice, _HbarUSDprice, _amount);
    }
    
    function acceptAskHbar(uint _orderId, uint _amount, uint _priceUSD, uint _HbarUSDprice) public payable {
        require(orders[_orderId].orderType == Ask);
        require(orders[_orderId].orderCurrencyType == Hbar);
        require(orders[_orderId].orderAmount >= _amount);
        uint askHbarPrice = orders[_orderId].orderPrice * _amount;
        require(askHbarPrice == msg.value);
        address ordersOwner = orders[_orderId].orderOwner;
        ordersOwner.transfer(askHbarPrice);
        mxi.transferFrom(orders[_orderId].orderOwner, msg.sender, _amount);
        emit AcceptHbarAsk(_orderId, _amount);
        orders[_orderId].orderAmount -= _amount;
        mxi.checkPrice(_priceUSD, orders[_orderId].orderPrice, _HbarUSDprice, _amount);
    }
    
    function acceptBidERC20(uint _orderId, uint _amount) public {
        require(orders[_orderId].orderAmount >= _amount);
        require(orders[_orderId].orderType == Bid);
        require(orders[_orderId].orderCurrencyType == ERC20);
        require(mxi.allowance(msg.sender, address(this)) >= _amount);
        uint bidERC20Price = orders[_orderId].orderPrice * _amount;
        address currencyAddress = orders[_orderId].orderCurrencyAddress;
        ERC20Interface(currencyAddress).transferFrom(orders[_orderId].orderOwner, msg.sender, bidERC20Price);
        mxi.transferFrom(msg.sender, orders[_orderId].orderOwner, _amount);
        emit AcceptERC20Bid();
        orders[_orderId].orderAmount -= _amount;
    }
    
    function acceptAskERC20(uint _orderId, uint _amount) public {
        require(orders[_orderId].orderAmount >= _amount);
        require(orders[_orderId].orderType == Ask);
        require(orders[_orderId].orderCurrencyType == ERC20);
        address currencyAddress = orders[_orderId].orderCurrencyAddress;
        require(ERC20Interface(currencyAddress).allowance(msg.sender, address(this)) >= _amount);
        uint askERC20Price = orders[_orderId].orderPrice * _amount;
        ERC20Interface(currencyAddress).transferFrom(msg.sender, orders[_orderId].orderOwner, askERC20Price);
        mxi.transferFrom(orders[_orderId].orderOwner, msg.sender, _amount);
        emit AcceptERC20Ask();
        orders[_orderId].orderAmount -= _amount;
    }
}
