pragma solidity >=0.4.25;
import "./AddressUtils.sol";

contract ERC20Interface {
    function allowance(address _from, address _to) public view returns(uint);
    function transferFrom(address _from, address _to, uint _sum) public;
    function transfer(address _to, uint _sum) public;
    function balanceOf(address _owner) public view returns(uint);
    function decimals() public view returns(uint8);
}

contract MXHederaDEX {
    
    event SetOrderHbarHBid();
    event SetOrderHbarAsk();
    event SetOrderERC20(OfferType indexed _orderType, uint indexed _orderId, uint _amount, uint _price, uint _lastTo, address _currencyAddress);
    event DeleteOrder(uint indexed _orderId);
    event AcceptHbarBid(uint indexed _orderId, uint _amount);
    event AcceptHbarAsk(uint indexed _orderId, uint _amount);
    event AcceptERC20Bid();
    event AcceptERC20Ask();
    
    enum OfferType {Bid, Ask}
    enum CurrencyType {Hbar, ERC20}
    
    using AddressUtils for address;
    address public owner;
    mapping(address => mapping(uint => uint)) public ordersByAddress;
    mapping(address => uint) public orderNumberByAddress;
    address public MXAddress;
    ERC20Interface mxi = ERC20Interface(MXAddress);

    struct Order {
        OfferType orderType;
        CurrencyType orderCurrencyType;
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
    }
    
    function setOrderHbarBid(uint _amount, uint _price, uint _lastTo) public payable {
        uint HbarBidPrice = _amount * _price;
        require(HbarBidPrice == msg.value); //take to setOrder
        orderId = orders.push(Order(OfferType.Bid, CurrencyType.Hbar, _amount, _price, now + _lastTo, address(0), msg.sender, HbarBidPrice)); 
        ordersByAddress[msg.sender][orderNumberByAddress[msg.sender]] = orderId;
        orderNumberByAddress[msg.sender] ++;
        orderCounter++;
        emit SetOrderHbarHBid();
    }

    function setOrderHbarAsk(uint _amount, uint _price, uint _lastTo) public {
        require(mxi.allowance(msg.sender, address(this)) >= _amount); //take to setOrder
        orderId = orders.push(Order(OfferType.Ask, CurrencyType.Hbar, _amount, _price, now + _lastTo, address(0), msg.sender, 0)); 
        ordersByAddress[msg.sender][orderNumberByAddress[msg.sender]] = orderId;
        orderNumberByAddress[msg.sender] ++;
        orderCounter++;
        emit SetOrderHbarAsk();
    }
    
    function setOrderERC20(OfferType _orderType, uint _amount, uint _price, uint _lastTo, address _currencyAddress) public {
        if(_orderType == OfferType.Bid) {
            require(ERC20Interface(_currencyAddress).allowance(msg.sender, address(this)) >= _amount);
        }
        if(_orderType == OfferType.Ask) {
            require(mxi.allowance(msg.sender, address(this)) >= _amount);
        }
        orderId = orders.push(Order(_orderType, CurrencyType.ERC20, _amount, _price, now + _lastTo, _currencyAddress, msg.sender, 0)); 
        ordersByAddress[msg.sender][orderNumberByAddress[msg.sender]] = orderId;
        orderNumberByAddress[msg.sender] ++;
        orderCounter++;
        emit SetOrderERC20(_orderType, orderId, _amount, _price, _lastTo, _currencyAddress);
    }
    
    function deleteOrder(uint _orderId) public onlyOwnerOf(_orderId) {
        address sendBack = orders[_orderId].orderOwner;
        sendBack.transfer(orders[_orderId].HbarBalance);
        orders[_orderId].orderAmount = 0;
        orders[_orderId].orderPrice = 0;
        orders[_orderId].orderLastTo = 0;
        orders[_orderId].orderOwner = address(0);
        orders[_orderId].orderCurrencyAddress = address(0);
        orders[_orderId].HbarBalance = 0;
        emit DeleteOrder(_orderId);
    }
    
    function acceptBidHbar(uint _orderId, uint _amount) public {
        require(orders[_orderId].orderType == OfferType.Bid);
        require(orders[_orderId].orderCurrencyType == CurrencyType.Hbar);
        require(orders[_orderId].orderAmount >= _amount);
        require(mxi.allowance(msg.sender, address(this)) >= _amount);
        uint bidHbarPrice = orders[_orderId].orderPrice * _amount;
        msg.sender.transfer(bidHbarPrice);
        mxi.transferFrom(msg.sender, orders[_orderId].orderOwner, _amount);
        emit AcceptHbarBid(_orderId, _amount);
         //Event
         orders[_orderId].orderAmount -= _amount;
         orders[_orderId].HbarBalance -= bidHbarPrice;
    }
    
    function acceptAskHbar(uint _orderId, uint _amount) public payable {
        require(orders[_orderId].orderType == OfferType.Ask);
        require(orders[_orderId].orderCurrencyType == CurrencyType.Hbar);
        require(orders[_orderId].orderAmount >= _amount);
        uint askHbarPrice = orders[_orderId].orderPrice * _amount;
        require(askHbarPrice == msg.value);
        address ordersOwner = orders[_orderId].orderOwner;
        ordersOwner.transfer(askHbarPrice);
        mxi.transferFrom(orders[_orderId].orderOwner, msg.sender, _amount);
        emit AcceptHbarAsk(_orderId, _amount);
        //Event
        orders[_orderId].orderAmount -= _amount;
    }
    
    function acceptBidERC20(uint _orderId, uint _amount) public {
        require(orders[_orderId].orderAmount >= _amount);
        require(orders[_orderId].orderType == OfferType.Bid);
        require(orders[_orderId].orderCurrencyType == CurrencyType.ERC20);
        require(mxi.allowance(msg.sender, address(this)) >= _amount);
        uint bidERC20Price = orders[_orderId].orderPrice * _amount;
        address currencyAddress = orders[_orderId].orderCurrencyAddress;
        ERC20Interface(currencyAddress).transferFrom(orders[_orderId].orderOwner, msg.sender, bidERC20Price);
        mxi.transferFrom(msg.sender, orders[_orderId].orderOwner, _amount);
        //Event
        orders[_orderId].orderAmount -= _amount;
    }
    
    function acceptAskERC20(uint _orderId, uint _amount) public {
        require(orders[_orderId].orderAmount >= _amount);
        require(orders[_orderId].orderType == OfferType.Ask);
        require(orders[_orderId].orderCurrencyType == CurrencyType.ERC20);
        address currencyAddress = orders[_orderId].orderCurrencyAddress;
        require(ERC20Interface(currencyAddress).allowance(msg.sender, address(this)) >= _amount);
        uint askERC20Price = orders[_orderId].orderPrice * _amount;
        ERC20Interface(currencyAddress).transferFrom(msg.sender, orders[_orderId].orderOwner, askERC20Price);
        mxi.transferFrom(orders[_orderId].orderOwner, msg.sender, _amount);
        //Event 
        orders[_orderId].orderAmount -= _amount;
    }
}
