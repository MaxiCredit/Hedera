pragma solidity >=0.4.25;

contract SimpleTokenInterface {
    function allowance(address _from, address _to) public view returns(uint);
    function transfer(address _to, uint _sum) public;
    function transferFrom(address _from, address _to, uint _sum) public;//Should use ERC20 like transferFrom to direct tansfer
    function transferFrom(address _from, address _to, uint _sum, uint _interestRate, bool _isRedeem) public;
    function getTokenBalance(address _owner) public view returns(uint);
    function transferLoan(address _to, uint _sum, uint _interestRate) public;
    function priceUSD() public view returns(uint);
}   

contract TestUsersInterface {
    function getUserPublicData(uint _id) public view returns(uint, uint);
    function checkUserPersonalID(uint _personalID) public view returns(bool);
    function checkUsersAddress(address _usersAddress) public view returns(bool);
    function getUsersAddress(uint _usersId, uint _counter) public view returns(address);
    function getUserByAddress(address _addr) public view returns(uint);
    function increaseCreditScore(uint _borrowerId, uint _interest, uint _interestRate, uint _creditId) public;
    function decreaseCreditScore(uint _borrowerId, uint _ratio, uint _creditId) public;
    function setCreditContractAddress(address _creditAddr, uint _userId, uint _loanId) public;
}

contract MXOptionInterface {
    function setOptions(address _addr, uint _amount, uint _exp, uint _price) public;
}

contract TestCreditContract {
    
    address SimpleTokenAddress = 0x000000000000000000000000000000000002EFcd;
    address MXOptionAddress = 0x000000000000000000000000000000000002E6D3;
    SimpleTokenInterface sti = SimpleTokenInterface(SimpleTokenAddress);
    MXOptionInterface moi = MXOptionInterface(MXOptionAddress);
    TestUsersInterface tui = TestUsersInterface(0x000000000000000000000000000000000002EFc9);
    
    uint public loanId;
    uint public lenderId;
    address public owner;
    uint public borrowerId;
    address borrowerAddress;
    uint public periods;
    uint public length;
    uint[] public loanExpiration; //DONT USE ZERO ELEMENT
    bool[] public paidBack; //DONT USE ZERO ELEMENT
    uint public latePeriodCounter; //1 latePeriod will be 10 day
    uint public start;
    uint public lastReedem = 0;
    uint public toPayBack;
    uint public totalPayBack;
    uint public a; //should rename periodLength
    uint public capital;
    uint public initialCapital;
    uint public interestRate;
    uint public salesPrice;
    bool public toSale;
    address public server;
    
    constructor(uint _loanId, uint _lenderId, uint _borrowerId, uint _capital, uint _interestRate, uint _period, uint _redeem, uint _length, address _server) public {
        loanId = _loanId;
        lenderId = _lenderId;
        owner = tui.getUsersAddress(lenderId, 0);
        borrowerId = _borrowerId;
        borrowerAddress = tui.getUsersAddress(borrowerId, 0);
        capital = _capital;
        initialCapital = _capital;
        interestRate = _interestRate;
        toPayBack = _redeem;
        start = now;
        periods = _period;
        totalPayBack = periods * toPayBack;
        length = _length;
        a = length / periods;
        for(uint i = 0; i <= _period; i++) {
            uint currentExpiration = a * i + now;
            loanExpiration.push(currentExpiration);
            moi.setOptions(borrowerAddress, toPayBack, currentExpiration, sti.priceUSD());
            paidBack.push(false);
        }
        server = _server;
        toSale = false;
        latePeriodCounter = 0;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    
    modifier onlyServer() {
        require(msg.sender == server);
        _;
    }
    
    //@@TODO events
    function latePayment() public onlyServer {
        uint latePeriodLength = 300; //It will be 10 days (864000s)
        uint creditScoreDropTime = 1200; //it will be 90 days (7776000s)
        if(now > (loanExpiration[lastReedem + 1] + (latePeriodCounter + 1) * latePeriodLength)) { 
            capital = capital * 101 / 100;   
            latePeriodCounter ++;
        }
        if(now > (loanExpiration[lastReedem + 1] + creditScoreDropTime)) {
            uint initialSumPayment = toPayBack * periods;
            uint notPaid = (periods - lastReedem) * toPayBack;
            uint ratio = notPaid * 100 / initialSumPayment;
            tui.decreaseCreditScore(borrowerId, ratio, loanId);
        }
    }
    
    //@@TODO events
    function setToRedeemed(uint _changeCapital) public onlyServer {
        lastReedem ++;
        paidBack[lastReedem] = true;
        capital -= _changeCapital;
        if(lastReedem == (periods - 1)) {
            toPayBack = capital * (100 + interestRate) / 100;
        }
        if(lastReedem == periods) {
            uint interest = totalPayBack - initialCapital;
            uint annualisedRate = annumRate();
            tui.increaseCreditScore(borrowerId, interest, annualisedRate, loanId);
        }
        latePeriodCounter = 0;
    }
    
    function getLoanID() public onlyServer view returns(uint) {
        return loanId;
    }
    
    //function getLoanOwner() public {}
    
    //Get initial capital,  interest rate, periods, redeem, length, start
    function getLoanInitialDetails() public view returns(uint, uint, uint, uint, uint, uint) {
        return(initialCapital, interestRate, toPayBack, periods, length, start);
    }
    
    //Get current capital, last redeem
    function getCurrentDetails() public view returns(uint, uint) {
        return(capital, lastReedem);
    }
    
    function getAllDetails() public view returns(uint, uint, uint, uint, uint, uint, uint, uint, uint) {
        return(loanId, initialCapital, interestRate, toPayBack, periods, length, start, capital, lastReedem);
    }
    
    function setToSale(uint _price) public onlyOwner {
        salesPrice = _price; //in Maxit
        toSale = true;
    }
    
    function deleteSale() public onlyOwner {
        toSale = false;
    }
    
    function buyCreditContract() public payable {
        require(toSale == true);
        require(msg.value == salesPrice);
        toSale = false;
        sti.transfer(owner, salesPrice);
        owner = msg.sender;
    }
    
    function transferCreditContract(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }
    
    //??? PERIODS
    function setRabat(uint _changeCapital, uint _changeInterest) public onlyOwner {
        require(_changeCapital <= capital);
        require(_changeInterest <= interestRate);
        capital -= _changeCapital;
        interestRate -= _changeInterest;
        uint remainingPeriods = periods - lastReedem; 
        toPayBack = calcRedeem(capital, remainingPeriods, interestRate);
        totalPayBack = toPayBack * periods;
    }
    
    function reStructure(uint _period) public onlyOwner {
        require(_period > periods);
        uint remainingPeriods = _period - lastReedem;
        toPayBack = calcRedeem(capital, remainingPeriods, interestRate);
        totalPayBack = toPayBack * _period;
    }
    
    //Reusable, should move to library
    //When floating point number will be fully supported should change the following 2 function for more precise algorithm 
    function calcRedeem (uint _amount, uint _period, uint _rate) private pure returns(uint) { 
        uint pow = 1;
        uint onePerPow = 1000000000000;
        uint ratePlus = _rate + 100;
        if(_period == 1) {
            pow *= ratePlus * 100;
        } else {
            for(uint i = 1; i <= _period; i++) {
                pow *= ratePlus;
                if(i > 2) {
                    pow /= 100; 
                }
            }
        }
        onePerPow /= pow;
        uint oneMinus = 100000000 - onePerPow;
        uint currentRedeem = uint(_amount * _rate * 1000000 / oneMinus);
        return(currentRedeem);
    }
    
    function annumRate() public view returns(uint){
        uint secInYears = 365 * 86400 * 100; //handling decimals
		uint loanLengthYearMultipliler = secInYears / length;
		uint annualRate = interestRate * periods * loanLengthYearMultipliler / 100;
		return annualRate;
    }
    
    function getBorrower(uint _id) public view returns(address) {
        return tui.getUsersAddress(borrowerId, _id);   
    }
}
