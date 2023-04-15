// SPDX-License-Identifier: CC-BY-4.0
pragma solidity >=0.7.0 <0.9.0;

interface OfferingTypeInterface {
    enum OfferingType {
        SECTION3A11,
        RULE147,
        RULE147A,
        SECTION4A2,
        RULE504,
        RULE505,
        RULE506B,
        RULE506C,
        RULE701,
        REGAT1,
        REGAT2,
        REGS,
        REGCF,
        S1,
        S3,
        F1,
        F3
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 tokens) external returns (bool);

    function name() external returns (string memory);
    function symbol() external returns (string memory);

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 tokens);
    event Buyerlist(address indexed tokenHolder);
    event issueDivi(address indexed tokenHolder,uint256 amount);
    event startSale(uint256 fromtime,uint256 totime,uint256 rate,uint256 supply);
}


interface OfferingInfoInterface {
    struct OfferingInfo {
        IERC20          token;
        string          name;
        string          symbol;
        uint256         maxShares;
        OfferingTypeInterface.OfferingType    offeringType;
        uint256         minOffering;
        uint256         maxOffering;
        uint256         started;            // epoch timestamp
        uint256         expiry;             // epoch timestamp, 0=no expiry
        uint256         maxAccredited;
        uint256         maxSophisticated;
        uint256         maxNonAccredited;
        uint256         lastTimeRequest;
        uint256         outstanding;
        uint256         remaining;
        string          cusip;
        string          isin;
        address         issuer;
        bool            restricted;
        bool            active;
        uint256         price; // initial share price
        uint256         bid;
        uint256         ask;
        uint256         fee; // transfer fee
        uint256         totalSupply;
        uint256         reserve;
    }    
}


contract ATS {

    string public TRADING_SYSTEM;

    address public immutable OWNER;

    string[] public symbols;

    struct ATSStorage {
        mapping (address => bool) transferAgent;

        mapping (address => bool) issuers;
        mapping (address => bool) accredited_investors;
        mapping (address => bool) nonaccredited_investors;
        mapping (address => bool) affiliated_investors;
        mapping (address => bool) broker_dealers;

        mapping (address => mapping (string => uint256)) balances;
        mapping (address => mapping (string => OfferingInfoInterface.OfferingInfo)) offering;
        mapping (address => uint256) fee;
    }

    function atsStorage() internal pure returns (ATSStorage storage ds)
    {
        bytes32 position = keccak256("ats.storage");
        assembly { ds.slot := position }
    }


    event SelfDestructing(string reason,uint256 amount);
    event TransferAgentAdded(address newAgent);
    event TransferAgentDisabled(address transferAgent);
    event InvestorAdded(address investor,string investor_type);
    event NewIssuerRegistered(address issuer);
    event NewSecurityRegistered(string symbol,address issuer,uint256 shares);
    event SecurityUpdated(string symbol,string action);
    event TransferFeeChange(address sender,address issuer,string symbol,uint256 fee);
    event TradingEnabled(address issuer,string symbol);
    event TradingStopped(address issuer,string symbol,string reason);
    event ExpiryUpdated(address issuer,string symbol,uint256 expiry);
    event MaximumAccreditedInvestorsUpdated(address issuer,string symbol,uint256 maxInvestors);
    event MaximumSophisticatedInvestorsUpdated(address issuer,string symbol,uint256 maxInvestors);
    event MaximumNonAccreditedInvestorsUpdated(address issuer,string symbol,uint256 maxInvestors);
    event OutstandingSharesUpdated(address issuer,string symbol,uint256 shares);
    event RemainingSharesUpdated(address issuer,string symbol,uint256 shares);
    event SecuirtyIsRestricted(address issuer,string symbol);
    event SecurityIsUnrestricted(address issuer,string symbol);
    event BidPriceUpdated(address transferAgent,address issuer,string symbol,uint256 bid);
    event AskPriceUpdated(address transferAgent,address issuer,string symbol,uint256 ask);
    event MinOfferingAmountUpdated(address transferAgent,address issuer,string symbol,uint256 amount);
    event MaxOfferingAmountUpdated(address transferAgent,address issuer,string symbol,uint256 amount);

    constructor(string memory _tradingSystemName) {
        OWNER = msg.sender;
        TRADING_SYSTEM = _tradingSystemName;
    }

    modifier isOwner() {
        require(msg.sender == OWNER,"not authorized");
        _;
    }

    modifier isTransferAgent() {
        require(atsStorage().transferAgent[msg.sender],"not valid transfer agent");
        _;
    }

    modifier isIssuer() {
        require(atsStorage().issuers[msg.sender],"not a permitted issuer");
        _;
    }

    modifier isIssuerOrTransferAgent() {
        require(atsStorage().transferAgent[msg.sender] || atsStorage().issuers[msg.sender],"not authorized, must be the issuer or a transfer agent");
        _;
    }

    modifier isBrokerDealer() {
        require(atsStorage().broker_dealers[msg.sender],"not a valid broker-dealer");
        _;
    }

    modifier isAccreditedInvestor() {
        require(atsStorage().accredited_investors[msg.sender],"not a valid accredited investor");
    }

    modifier isAccreditedInvestorOrBrokerDealer() {
        require(atsStorage().accredited_investors[msg.sender] || atsStorage().broker_dealers[msg.sender],"not a accredited investor nor a broker-dealer");
        _;
    }

    modifier isTransferAgentOrBrokerDealer() {
        require(atsStorage().transferAgent[msg.sender] || atsStorage().broker_dealers[msg.sender],"not a transfer agent nor a broker-dealer");
        _;
    }

    /*
     * A Transfer Agent is required. The transfer agent can be the issuer or registered broker-dealer, before a 
     * new security is registered.
     */
    function addTransferAgent(address _transferAgent) public isOwner {
        require(atsStorage().transferAgent[_transferAgent] == false,"Already added as a transfer agent");
        atsStorage().transferAgent[_transferAgent] = true;
        emit TransferAgentAdded(_transferAgent);
    }
    function disableTransferAgent(address _transferAgent) public isOwner {
        require(atsStorage().transferAgent[_transferAgent] == true,"not a transfer agent");
        atsStorage().transferAgent[_transferAgent] = false;
        emit TransferAgentDisabled(_transferAgent);
    }
    /*
     * An issuer must be added before a new security can be registered. Only the transfer agent can add an issuer.
     */
    function addIssuer(address _issuer) public isTransferAgent {
        require(atsStorage().issuers[_issuer] == false,"issuer has already been added");
        atsStorage().issuers[_issuer] = true;
        emit InvestorAdded(_issuer, "issuer");
    }
    /*
     */
    function registerSecurity(address _issuer, OfferingTypeInterface.OfferingType _offeringType,address _token,string memory _symbol) public isIssuerOrTransferAgent {
        require(atsStorage().offering[_issuer][_symbol].active == false,"security is already registered");
    
        atsStorage().offering[_issuer][_symbol].token = IERC20(_token);
        atsStorage().offering[_issuer][_symbol].name = IERC20(_token).name();
        atsStorage().offering[_issuer][_symbol].symbol = _symbol;
        atsStorage().offering[_issuer][_symbol].offeringType = _offeringType;
        atsStorage().offering[_issuer][_symbol].started = 0;
        atsStorage().offering[_issuer][_symbol].expiry = 0;
        atsStorage().offering[_issuer][_symbol].maxShares = IERC20(_token).totalSupply();
        atsStorage().offering[_issuer][_symbol].totalSupply = IERC20(_token).totalSupply();
    
        if (atsStorage().issuers[msg.sender]) {
            // issuer is registering the offering
            atsStorage().offering[_issuer][_symbol].issuer = msg.sender;
        } else {
            // transfer agent is registering the offering
            require(atsStorage().issuers[_issuer],"not valid issuer");
            atsStorage().offering[_issuer][_symbol].issuer = _issuer;
        }
    }

    function updateCUSIP(address _issuer,string memory _symbol,string memory _cusip) public isTransferAgent {
        require(atsStorage().offering[_issuer][_symbol].active,"security is not registered");
        atsStorage().offering[_issuer][_symbol].cusip = _cusip;
        emit SecurityUpdated(atsStorage().offering[_issuer][_symbol].symbol, "CUSIP updated");
    }

    function updateISIN(address _issuer,string memory _symbol,string memory _isin) public isTransferAgent {
        require(atsStorage().offering[_issuer][_symbol].active,"security is not registered");
        atsStorage().offering[_issuer][_symbol].isin = _isin;
        emit SecurityUpdated(atsStorage().offering[_issuer][_symbol].symbol, "ISIN updated");
    }

    function setExpiry(address _issuer,string memory _symbol,uint256 _expiry) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].expiry = _expiry;
        emit ExpiryUpdated(_issuer,_symbol,_expiry);
    }

    function startAcceptionTrades(address _issuer,string memory _symbol)  public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].active = true;
        atsStorage().offering[_issuer][_symbol].started = block.timestamp;
        emit TradingEnabled(_issuer,_symbol);        
    }
    function stopAcceptingTrades(address _issuer,string memory _symbol,string memory _reason) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].active = false;
        emit TradingStopped(_issuer,_symbol,_reason);
    }    
    function setMaxAccreditedInvestors(address _issuer,string memory _symbol,uint256 _maxInvestors) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].maxAccredited = _maxInvestors;
        emit MaximumAccreditedInvestorsUpdated(_issuer,_symbol,_maxInvestors);
    }
    function setMaxSophisticatedInvestors(address _issuer,string memory _symbol,uint256 _maxInvestors) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].maxSophisticated = _maxInvestors;
        emit MaximumSophisticatedInvestorsUpdated(_issuer,_symbol,_maxInvestors);
    }
    function setMaxNonAccreditedInvestors(address _issuer,string memory _symbol,uint256 _maxInvestors) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].maxNonAccredited = _maxInvestors;
        emit MaximumNonAccreditedInvestorsUpdated(_issuer,_symbol,_maxInvestors);
    }
    function updateOutstandingShares(address _issuer,string memory _symbol,uint256 _shares) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].outstanding = _shares;
        emit OutstandingSharesUpdated(_issuer,_symbol,_shares);
    }
    function updateRemainingShares(address _issuer,string memory _symbol,uint256 _shares) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].remaining = _shares;
        emit RemainingSharesUpdated(_issuer,_symbol,_shares);
    }
    function setRestrictedSecurity(address _issuer,string memory _symbol) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].restricted = true;
        emit SecuirtyIsRestricted(_issuer,_symbol);
    }
    function setUnRestrictedSecurity(address _issuer,string memory _symbol) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].restricted = false;
        emit SecurityIsUnrestricted(_issuer,_symbol);
    }

    /*
     * Investor types
     */
    function addAcreditedInvestor(address _investor) public isTransferAgentOrBrokerDealer {
        require(atsStorage().accredited_investors[_investor] == false,"accredited investor is already added");
        atsStorage().accredited_investors[_investor] = true;
        emit InvestorAdded(_investor, "accredited-investor");
    }
    function addNonAccreditedInvestor(address _investor) public isTransferAgentOrBrokerDealer {
        require(atsStorage().nonaccredited_investors[_investor] == false,"non-accredited investor is already added");
        atsStorage().nonaccredited_investors[_investor] = true;
        emit InvestorAdded(_investor, "non-accredited investor");
    }
    function addAffiliatedInvestor(address _investor) public isTransferAgentOrBrokerDealer {
        require(atsStorage().affiliated_investors[_investor] == false,"affiliated investor is already added");
        atsStorage().affiliated_investors[_investor] = true;
        emit InvestorAdded(_investor, "affiliated-investor");
    }
    function addBrokerDealer(address _brokerDealer) public isTransferAgent {
        require(atsStorage().broker_dealers[_brokerDealer] == false,"broker-dealer is already added");
        atsStorage().broker_dealers[_brokerDealer] = true;
        emit InvestorAdded(_brokerDealer, "broker-dealer");
    }
    function setFee(address _issuer,string memory _symbol,uint256 _fee) public isTransferAgent {
        require(_fee < 1000,"fee must be greater than 1% (<1000)");
        atsStorage().offering[_issuer][_symbol].fee = _fee;
        emit TransferFeeChange(msg.sender,_issuer,_symbol,_fee);
    }
    function setBid(address _issuer,string memory _symbol,uint256 _bid) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].bid = _bid;
        emit BidPriceUpdated(msg.sender,_issuer,_symbol,_bid);
    }
    function setAsk(address _issuer,string memory _symbol,uint256 _ask) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].ask = _ask;
        emit AskPriceUpdated(msg.sender,_issuer,_symbol,_ask);
    }
    function setMinOfferingAmount(address _issuer,string memory _symbol,uint256 _amount) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].minOffering = _amount;
        emit MinOfferingAmountUpdated(msg.sender,_issuer,_symbol,_amount);
    }
    function setMaxOfferingAmount(address _issuer,string memory _symbol,uint256 _amount) public isTransferAgent {
        atsStorage().offering[_issuer][_symbol].maxOffering = _amount;
        emit MaxOfferingAmountUpdated(msg.sender,_issuer,_symbol,_amount);
    }

    function swap(address _issuer,string memory _symbol,address _tokenIn,address _tokenOut,uint256 _amountIn) external returns (uint amountOut) {
        require(_tokenIn == address(atsStorage().offering[_issuer][_symbol].token),"invalid token");
        require(_amountIn > 0,"amount in = 0");

        // Pull in token in
        IERC20 tokenIn = atsStorage().offering[_issuer][_symbol].token;
        tokenIn.transferFrom(msg.sender,address(this),_amountIn);

        // Calculate token out (include fees), fee 0.3%
        uint amountInWithFee = atsStorage().offering[_issuer][_symbol].fee / 1000;
        amountOut = (atsStorage().offering[_issuer][_symbol].reserve * amountInWithFee) / (atsStorage().offering[_issuer][_symbol].reserve + amountInWithFee);
        // Transfer token out to msg.sender
        IERC20 tokenOut = IERC20(_tokenOut);
        tokenOut.transfer(msg.sender,amountOut);
        // Update reserves
        _update(_issuer,_symbol,atsStorage().offering[_issuer][_symbol].token.balanceOf(address(this)));
    }


    function buyForResale(address payable _issuer,string memory _symbol,uint256 _amount) public payable isBrokerDealer {
        require(atsStorage().offering[_issuer][_symbol].active,"offering does not exists");
        require(msg.value >= atsStorage().offering[_issuer][_symbol].price * _amount,"insufficient funds to purchase");
        //require(atsStorage().offering[_issuer][_symbol].started > 0,"offering has not started");
        //require(atsStorage().offering[_issuer][_symbol].started > block.timestamp,"offering has not started");
        if (atsStorage().offering[_issuer][_symbol].expiry > 0) {
            require(atsStorage().offering[_issuer][_symbol].expiry < block.timestamp,"offering has expired");
        }
        
        require(_amount >= atsStorage().offering[_issuer][_symbol].minOffering,"purchase amount is less than minimum offering");
        require(_amount < atsStorage().offering[_issuer][_symbol].maxOffering,"purchase amount exceeds the maximum offering amount");

        require(_amount <= atsStorage().offering[_issuer][_symbol].maxShares - atsStorage().offering[_issuer][_symbol].outstanding,"not enough available shares to purchase");

        atsStorage().offering[_issuer][_symbol].outstanding += _amount;
        atsStorage().offering[_issuer][_symbol].remaining -= _amount;

        atsStorage().balances[msg.sender][atsStorage().offering[_issuer][_symbol].symbol] += _amount;

        uint256 total = atsStorage().offering[_issuer][_symbol].price * _amount;
        uint256 totalWithFee = total * (atsStorage().offering[_issuer][_symbol].fee / 1000); // 997 / 1000; // 3% fee to the issuer
        uint256 fee = total - totalWithFee;

        payable(atsStorage().offering[_issuer][_symbol].issuer).transfer(totalWithFee);
        payable(address(this)).transfer(fee);
    }

    function addLiquidity(address payable _issuer,string memory _symbol,uint256 _amount) external payable isAccreditedInvestorOrBrokerDealer returns (uint shares) {
        // liquidity may added ONLY for active and non-expired offerings
        require(atsStorage().offering[_issuer][_symbol].active == true && atsStorage().offering[_issuer][_symbol].expiry > block.timestamp,"liquidity only available for active or non-expired offerings");

        // Pull in token0 and token1
        atsStorage().offering[_issuer][_symbol].token.transferFrom(msg.sender,address(this),_amount);

        // Update reserves
        _update(_issuer,_symbol,atsStorage().offering[_issuer][_symbol].token.balanceOf(address(this)));

        // Mint shares
        shares = (_amount * atsStorage().offering[_issuer][_symbol].totalSupply) / atsStorage().offering[_issuer][_symbol].reserve;
        require(shares > 0,"shares are zero");
        _mint(_issuer,_symbol,msg.sender,shares);
    }

    function removeLiquidity(address payable _issuer,string memory _symbol,uint _shares) external payable isAccreditedInvestorOrBrokerDealer returns (uint amount) {
        // withdrawals from liquidity ONLY permitted when the offering is NOT active or expired offerings
        require(atsStorage().offering[_issuer][_symbol].active == false || atsStorage().offering[_issuer][_symbol].expiry < block.timestamp,"no withdrawals permitted for active or non-expired offerings");

        // Calculate amoutn0 and amount1 to withdraw
        uint256 bal = atsStorage().offering[_issuer][_symbol].token.balanceOf(address(this));

        amount = (_shares * bal) / atsStorage().offering[_issuer][_symbol].totalSupply;
        require(amount > 0, "amounts are zero");

        // Burn shares
        _burn(_issuer,_symbol,msg.sender,_shares);
        // Update shares
        _update(_issuer,_symbol,bal - amount);
        // Transfer tokens to msg.sender
        atsStorage().offering[_issuer][_symbol].token.transfer(msg.sender,amount);
    }


    function getBalance(address _issuer,string memory _symbol) public view returns(uint256) {
        require(atsStorage().offering[_issuer][_symbol].active,"offering does not exists");
        return atsStorage().balances[msg.sender][atsStorage().offering[_issuer][_symbol].symbol];
    }

    function getOfferingType(address _issuer,string memory _symbol) public view returns (OfferingTypeInterface.OfferingType) {
        return atsStorage().offering[_issuer][_symbol].offeringType;
    }

    function getOffering(address _issuer,string memory _symbol) public view returns (OfferingInfoInterface.OfferingInfo memory) {
        return atsStorage().offering[_issuer][_symbol];
    }

    function _update(address _issuer,string memory _symbol,uint _reserve) private {
        atsStorage().offering[_issuer][_symbol].reserve = _reserve;
    }

    function _mint(address _issuer,string memory _symbol,address _to,uint _amount) private {
        atsStorage().balances[_to][atsStorage().offering[_issuer][_symbol].symbol]+= _amount;
        atsStorage().offering[_issuer][_symbol].totalSupply += _amount;
    }

    function _burn(address _issuer,string memory _symbol,address _from,uint _amount) private {
        atsStorage().balances[_from][atsStorage().offering[_issuer][_symbol].symbol] -= _amount;
        atsStorage().offering[_issuer][_symbol].totalSupply -= _amount;
    }

    function _sqrt(uint y) private pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while(x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint x,uint y) private pure returns (uint) {
        return x <= y ? x : y;
    }

}