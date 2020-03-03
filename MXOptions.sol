pragma solidity >=0.4.25;

import "./ERC20.sol";
import "./TestCredit.sol";

contract MXInterface {
    function allowance(address _from, address _to) public view returns(uint);
    function transfer(address _to, uint _sum) public;
    function transferFrom(address _from, address _to, uint _sum) public;
    function transferFrom(address _from, address _to, uint _sum, uint _interestRate, bool _isRedeem) public;
    function getTokenBalance(address _owner) public view returns(uint);
} 

contract MXOptions is ERC20("MX Option", "MX Opt", 0) {
    
    address public CreditCreatorAddress;
    address public MXAddress;
    MXInterface mxi = MXInterface(MXAddress);
    address public owner;
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    modifier onlyCreditCreator {
        require(msg.sender == CreditCreatorAddress);
        _;
    }
    
    constructor() public {
        owner = msg.sender;
    }
    
    function setCreditCreatorAddress(address _addr) public onlyOwner {
        require(_addr != address(0));
        CreditCreatorAddress = _addr;
    }
    
    function setMXAddress(address _addr) public onlyOwner {
        require(_addr != address(0));
        MXAddress = _addr;
    }
    
    struct Option {
        address owner;
        uint amount;
        uint exp;
        uint price;
    }
    Option[] public options;
    
    function setOptions(address _addr, uint _amount, uint _exp, uint _price) public onlyCreditCreator {
        options.push(Option(_addr, _amount, _exp, _price));
        mint(_addr, _amount);
    }
    
    function getOptions(uint _id, uint _amount) public payable {
        require(msg.value == _amount * options[_id].price);
        require(msg.sender == options[_id].owner);
        require(now > options[_id].exp && now < options[_id].exp + 86400);
        options[_id].amount -= _amount;
        _burn(msg.sender, _amount);
        mxi.transfer(options[_id].owner, _amount);      
    }

}
