pragma solidity ^0.5.16;


// The cMDL Token Contract
contract cMDL_v1 {    

    /** Paramaeters **/
    // Core
    uint256 public emissionAmount; // amount of cMDLs distributed to each account during the emissionPeriod
    uint256 public emissionPeriod; // number of blocks between emissions
    
    uint8 public inactivityPeriods = 4; // number of claims missed before an account can be marked as inactive

    // Burn Fees
    uint256 public burnFee; // the burn fee proportion deducted from each cMDL transfer (1 = 1e18, 0.001 (0.1%) = 1e15 etc)
    
    // Voting Contract
    address public votingContract; // the account controlling cMDL parameters

    // Operator
    address public operatorAccount; // account that changes the mintAccount and can block/unblock accounts, operator account also distributes Rinkeby ETH to all accounts to allow for free transfers
    address public mintAccount; // account that is allowed to mint initial payments
    
    
    
    




    /** Events **/
    // Parameters
    event emissionParametersChanged(uint256 newEmissionAmount, uint256 newEmissionPeriod); // fired when emission parameters are changed
    event operatorChanged(address indexed newOperatorAccount); // fired when operatorAccount is modified
    event mintAccountChanged(address indexed newMintAccount); // fired when mint account is changed
    event votingContractChanged(address indexed newVotingContract); // fired when mint account is changed
    event chargedProposalFee(address indexed account, uint256 fee); // fired when a proposal fee is charged
   
    // Operator
    event minted(address indexed account, uint256 indexed id); // when the first payment is sent to a young account this event is fired
    event userBlocked(address indexed account, bool blocked); // fired when an account is blocked or unblocked
    event userSetInactive(address account); // fired when an account is marked as inactive
    
    // User
    event claimed(address indexed account, uint256 amount); // fired on each emission claim performed by user
    event recurringPaymentCreated(address indexed _from, address indexed recipientAccount,  bytes32 recurringPaymentHash, uint256 paymentAmount, uint256 paymentPeriod); // fired when a recurring payment is created
    event recurringPaymentMade(bytes32 indexed hash, address indexed sender, address indexed receiver, uint256 paymentAmount);
    event recurringPaymentCancelled(bytes32 indexed hash, address indexed sender, address indexed receiver, uint256 paymentAmount);

    // Burn fee
    event burnFeeChanged(uint256 newBurnFee); // fired when the burnFee is changed
    




    /**
     * cMDL Functions
     * */

    /** Emission Functionality **/  
    // Internal parameters
    mapping (address => uint256)    public lastEmissionClaimBlock; // mapping of user accounts and their respective last emission claim blocks
    mapping (address => uint256)    public balance; // holds
    mapping (uint256 => address)    public accounts; // mapping of ID numbers (eg. Facebook UID) to account addresses 
    mapping (address => uint256)    public ids; // inverse mapping of accounts
    mapping (address => bool)       public blocked; // keeps list of accounts blocked for emissions
    mapping (address => bool)       public inactive; // mapping of inactive accounts, an account can be set as inactive if it doesn't claim the emission for more than 4 consecutive emission periods
    mapping (bytes32 => bool)       public claim; // mapping of claim hashes that have been executed

    uint256 public active; // number of active (voting) accounts


    


    /** User Functions **/
    enum SignatureType {
        /*  0 */EMISSION_CLAIM,                 
        /*  1 */RECURRING_PAYMENT_CREATE,                
        /*  2 */RECURRING_PAYMENT_CANCEL
    }

    // Claim emission function called by the holder once each emission period
    function claimEmission() external {
        processEmissionClaim(msg.sender);
    }

    function signedEmissionClaim(address account, uint256 nonce, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 emissionHash = keccak256(this, account, nonce, uint8(SignatureType.EMISSION_CLAIM));
        require(ecrecover(keccak256("\x19Ethereum Signed Message:\n32", emissionHash), v, r, s) == account), "cMDL Error: invalid signature");
        require(!claim[emissionHash], "cMDL Error: emission already claimed");

        claim[emissionHash] = true;

        claimEmission(account);
    }

    function claimEmission(address account) internal {
        require(safeSub(block.number, lastEmissionClaimBlock[account]) > emissionPeriod, "cMDL Error: emission period did not pass yet");

        require(lastEmissionClaimBlock[account] > 0, "cMDL Error: account not registered");
        require(!blocked[account], "cMDL Error: account blocked");

        uint256 taxAmount = safeMul(emissionAmount, taxProportion)/1e18;
        uint256 netAmount = safeSub(emissionAmount, taxAmount);

        balanceOf[account] = safeAdd(balanceOf[account], netAmount);
        
        
        lastEmissionClaimBlock[account] = block.number;
        totalSupply = safeAdd(totalSupply, emissionAmount);

        if (inactive[account])
        {
            setActive(account);
        }

        emit claimed(account, emissionAmount);
        emit Transfer(address(0), account, emissionAmount);
    }
    
    
    
    // Recurring payments
    struct RecurringPayment {
        uint256 paymentAmount; // the recurring payment amount
        uint256 recurringPeriod; // the recurring period
        uint256 expires; // the block number when the recurring payment ends
        uint256 lastPayment; // the block number of the last payment
    }
    
    //       hash               from
    mapping (bytes32 => RecurringPayment) public recurringPayments; // mapping of recurring payments
    
    function createRecurringPayment(uint256 paymentAmount, uint256 recurringPeriod, address recipientAccount, uint256 expires) external {
        createRecurringPaymentInternal(msg.sender, paymentAmount, recurringPeriod, recipientAccount, expires);
    }

    function signedCreateRecurringPayment(address account, uint256 paymentAmount, uint256 recurringPeriod, address recipientAccount, uint256 expires, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 recurringPaymentHash = keccak256(this, msg.sender, recipientAccount, paymentAmount, paymentPeriod, uint8(SignatureType.RECURRING_PAYMENT_CREATE));
        require(ecrecover(keccak256("\x19Ethereum Signed Message:\n32", recurringPaymentHash), v, r, s) == account), "cMDL Error: invalid signature");

        createRecurringPaymentInternal(account, paymentAmount, recurringPeriod, recipientAccount, expires);
    }

    function createRecurringPaymentInternal(address account, uint256 paymentAmount, uint256 recurringPeriod, address recipientAccount, uint256 expires) internal {
        bytes32 recurringPaymentHash = keccak256(this, account, recipientAccount, paymentAmount, paymentPeriod);
        
        recurringPayments[recurringPaymentHash] = RecurringPayment({
            sender            : account,
            receiver          : recipientAccount,
            paymentAmount     : paymentAmount,
            recurringPeriod   : recurringPeriod,
            expires           : expires,
            startBlock        : block.number,
            lastPayment       : 0
        });
        
        emit recurringPaymentCreated(account, recipientAccount, recurringPaymentHash, paymentAmount, paymentPeriod);
    }
    
    function claimRecurringPaymentForUser(address account, bytes32 hash) external {
        require(recurringPayments[hash].paymentAmount > 0, "cMDL Error: recurring oayment not found");
        require(recurringPayments[hash].expires > block.number, "cMDL Error: recurring payment expired");
        
        uint8 paymentsAvailable = safeSub(block.number, max(startBlock, lastPayment)) / reccuringPeriod;
        
        require(paymentsAvailable > 0, "cMDL Error: no payments available");
        
        recurringPayments[hash].lastPayment = block.number;
        
        _transfer(recurringPayments[hash].sender, recurringPayments[hash].receiver, paymentAmount);
        
        emit recurringPaymentMade(hash, recurringPayments[hash].sender, recurringPayments[hash].receiver, paymentAmount);
    }

    // claim a recurring payment
    function claimRecurringPayment(bytes32 hash) external {
        require(recurringPayments[hash].paymentAmount > 0, "cMDL Error: recurring oayment not found");
        require(recurringPayments[hash].expires > block.number, "cMDL Error: recurring payment expired");
        
        uint8 paymentsAvailable = safeSub(block.number, max(startBlock, lastPayment)) / reccuringPeriod;
        
        require(paymentsAvailable > 0, "cMDL Error: no payments available");
        
        recurringPayments[hash].lastPayment = block.number;
        
        _transfer(recurringPayments[hash].sender, recurringPayments[hash].receiver, paymentAmount);
        
        emit recurringPaymentMade(hash, recurringPayments[hash].sender, recurringPayments[hash].receiver, paymentAmount);
    }

    function cancelRecurringPayment(bytes32 hash) external {
        cancelRecurringPaymentInternal(msg.sender, hash);
    }

    function signedCancelRecurringPayment(address account, bytes32 hash, uint256 nonce, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 cancelHash = keccak256(this, account, nonce, uint8());
        require(ecrecover(keccak256("\x19Ethereum Signed Message:\n32", emissionHash), v, r, s) == account), "cMDL Error: invalid signature");
        cancelRecurringPaymentInternal(msg.sender, hash);
    }
    
    // cancel an existing recurring payment
    function cancelRecurringPaymentInternal(address account, bytes32 hash) internal {
        require(recurringPayments[hash].paymentAmount > 0, "cMDL Error: recurring oayment not found");
        require(account == recurringPayments[hash].sender, "cMDL Error: access denied");
        
        recurringPayments[hash].expires = block.number;
        
        emit recurringPaymentCancelled(hash, account, recurringPayments[hash].receiver, recurringPayments[hash].paymentAmount);
    }    

    // function called by the votingContract to charge the user for creating a proposal
    function chargeUserForProposal(address account) external onlyVote  {
        require(balanceOf[account] >= emissionAmount, "cMDL Error: insufficient balance");

        burnForUser(account, emissionAmount);

        emit chargedProposalFee(account, emissionAmount);
    }
    
    
    
    
    
    /** Operator Functions **/
    // Mint the initial payment
    function mint(address account, uint256 id) external onlyMint {
        require(lastEmissionClaimBlock[account] == 0, "cMDL Error: account already registered");
        require(accounts[id] == address(0), "cMDL Error: account with this ID already exists");
        require(mintAccount != account, "cMDL Error: cannot mint to mintAccount");

        uint256 taxAmount = safeMul(emissionAmount, taxProportion)/1e18;
        uint256 netAmount = safeSub(emissionAmount, taxAmount);

        balanceOf[account] = safeAdd(balanceOf[account], netAmount);
        balanceOf[taxAccount] = safeAdd(balanceOf[taxAccount], taxAmount);

        lastEmissionClaimBlock[account] = block.number;

        accounts[id] = account;
        ids[account] = id;

        totalSupply = safeAdd(totalSupply, emissionAmount);

        active = safeAdd(active, 1);

        emit minted(account, id);
        emit claimed(account, emissionAmount);
        emit Transfer(address(0), msg.sender, emissionAmount); 
        emit Transfer(address(0), taxAccount, taxAmount); 
    }

    // Block account, prevents account from claimin emissions
    function blockAccount(address account) external onlyOperator {
        blocked[account] = true;

        active = safeSub(active, 1);

        emit userBlocked(account, true);
    }

    // Unblock account, removes block from account
    function unBlockAccount(address account) external onlyOperator {
        blocked[account] = false;

        active = safeAdd(active, 1);

        emit userBlocked(account, false);
    }

    // Set an account as inactive
    function setInactive(address account) external onlyMint {
        require(lastEmissionClaimBlock[account] < safeSub(block.number, safeMul(emissionPeriod, inactivityPeriods)), "cMDL Error: account was active during the active period");
        require(lastEmissionClaimBlock[account] > 0, "cMDL Error: account not registered");

        inactive[account] = true;
        active = safeSub(active, 1);

        emit userSetInactive(account);
    }

    // Sets account as active and increases the number of active accounts (registered)
    // can only be called from the claim function
    function setActive(address account) internal {
        inactive[account] = false;
        active = safeAdd(active, 1);
    }










    /** Parameter Functionality **/    
    // the function called by the votingContract to change the cMDL emission parameters
    function changeEmissionParameters(uint256 emissionAmount_, uint256 emissionPeriod_) external onlyVote returns (bool success) {
        require(emissionAmount_ < safeMul(emissionAmount, 1618)/1000 && emissionAmount_ > safeMul(emissionAmount, 618)/1000, "cMDL Error: emissionSize out of bounds");

        emissionAmount = emissionAmount_;
        emissionPeriod = emissionPeriod_;

        emit emissionParametersChanged(emissionAmount, emissionPeriod);
        return true;
    }

    // function called by the votingContract to change the cMDL operatorAccount
    function changeOperatorAccount(address operatorAccount_) external onlyVote returns (bool success)  {
        operatorAccount = operatorAccount_;

        emit operatorChanged(operatorAccount);
        return true;
    }

    // function called by the operatorAccount to change the mint account address
    function changeMintAccount(address mintAccount_) external onlyOperator  {
        mintAccount = mintAccount_;

        emit mintAccountChanged(mintAccount);
    }

    // function called by the votingContract to change the admin account address, in case it is necessary
    // to upgrade the Admin votting contract
    function changeVotingContract(address votingContract_) external onlyVote  {
        votingContract = votingContract_;

        emit votingContractChanged(votingContract_);
    }
        

    /** Transaction Burn Fee Functionality **/
    // Transaction burn fee is the fee taken during each transfer from the transferred amount and burnt.
    // This is necessary to combat inflation, through the burn fee, the total supply of cMDL is decreased 
    // as the transferred volume increases
    
    // the function called by the vottingContract to change the burnFee
    function changeBurnFee(uint256 burnFee_) external onlyOperator {
        require(burnFee_ < 5e16, "cMDL Error: burn fee cannot be higher than 5%");

        burnFee = burnFee_;
        emit burnFeeChanged(burnFee);
    }
    
    
    
    


    /** Internal Functionality **/

    /** Constructor **/
    // Constructor function, called once when deploying the contract
    constructor(
        string memory name_,
        string memory symbol_,

        uint256 maxTaxProportion_,
        uint256 maxTxFee_,

        uint256 initialEmissionAmount, 
        uint256 initialEmissionPeriod, 
        uint256 initialTaxProportion,
        uint256 initialTxFee,
        uint256 initialBurnFee,
        
        uint256 initialMaxOperatorMultiplier,

        address initialVotingContract, 
        address initialOperatorAccount, 
        address initialMintAccount,
        address initialTaxAccount,
        address initialTxFeeAccount
    ) public
    {
        name = name_;
        symbol = symbol_;

        maxTaxProportion= maxTaxProportion_;
        maxTxFee        = maxTxFee_;

        emissionAmount  = initialEmissionAmount;
        emissionPeriod  = initialEmissionPeriod;
        taxProportion   = initialTaxProportion;
        txFee           = initialTxFee;
        burnFee         = initialBurnFee;
        maxOperatorMultiplier = initialMaxOperatorMultiplier;

        votingContract = initialVotingContract;
        operatorAccount = initialOperatorAccount;
        mintAccount     = initialMintAccount;
        taxAccount      = initialTaxAccount;
        txFeeAccount    = initialTxFeeAccount;
    }




    /** Modifiers **/
    // a modifier that allows only the votingContract to access a function
    modifier onlyVote {
        require(msg.sender == votingContract, "cMDL Error: accesses denied");
        _;
    }

    // a modifier that allows only the mintAccount to access a function
    modifier onlyMint {
        require(msg.sender == mintAccount || msg.sender == operatorAccount, "cMDL Error: accesses denied");
        _;
    }

    // a modifier that allows only the operatorAccount to access a function
    modifier onlyOperator {
        require(msg.sender == operatorAccount, "cMDL Error: accesses denied");
        _;
    }


    /** Helpers **/
    // Returns the smaller of two values
    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }

    // Returns the largest of the two values
    function max(uint a, uint b) private pure returns (uint) {
        return a > b ? a : b;
    }
    
    // Returns the number of active accounts
    function getActive() public view returns (uint256)
    {
        return active;
    }
    
    // Returns true if the account is registered
    function isRegistered(address account) public view returns (bool registered)
    {
        if (lastEmissionClaimBlock[account] > 0)
        {
            return true;
        }
        else
        {
            return false;
        }
    }














    /** ERC20 Implementation 
    * https://eips.ethereum.org/EIPS/eip-20
    **/
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply = 0;

    mapping (address => uint256) public balanceOf; // keeps the balances of all accounts
    mapping (address => mapping (address => uint256)) public allowance; // keeps allowences for all accounts (implementation of the ERC20 interface)

    // This generates a public event on the blockchain that will notify clients
    event Transfer(address indexed from, address indexed to, uint256 value); // This generates a public event on the blockchain that will notify clients (ERC20 interface)
    
    // This generates a public event on the blockchain that will notify clients
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    
    // This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);

    /**
     * Internal transfer, only can be called by this contract
     */
    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(address(_to) != address(0));        

        // Add the same to the recipient minus the txFee
        uint256 txFeeAmount = safeMul(_value, txFee)/1e18;
        uint256 burnFeeAmount = safeMul(_value, burnFee)/1e18;

        // Subtract from the sender
        balanceOf[_from] = safeSub(balanceOf[_from], _value);
        balanceOf[_to] = safeAdd(balanceOf[_to], _value);
        burnForUser(_to, burnFeeAmount);

        emit Transfer(_from, _to, _value);
    }

    /**
     * Transfer tokens
     *
     * Send `_value` tokens to `_to` from your account
     *
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transfer(address _to, uint256 _value) public returns (bool success) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /**
     * Signed Transfer
     *
     * Send `_value` tokens to `_to` from `_account`
     *
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function signedTransfer(address _to, uint256 _value, address _account, uint256 nonce, uint8 v, bytes32 r, bytes32 s) public returns (bool success) {
        bytes32 transferHash = keccak256(this, _account, _to, _value, nonce);
        require(ecrecover(keccak256("\x19Ethereum Signed Message:\n32", transferHash), v, r, s) == _account), "cMDL Error: invalid signature");

        _transfer(_account, _to, _value);
        return true;
    }

    /**
     * Transfer tokens from other address
     *
     * Send `_value` tokens to `_to` on behalf of `_from`
     *
     * @param _from The address of the sender
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);     // Check allowance
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }

    /**
     * Set allowance for other address
     *
     * Allows `_spender` to spend no more than `_value` tokens on your behalf
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     */
    function approve(address _spender, uint256 _value) public
        returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
     * Destroy tokens
     *
     * Remove `_value` tokens from the system irreversibly
     *
     * @param _value the amount of money to burn
     */
    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);   // Check if the sender has enough
        balanceOf[msg.sender] -= _value;            // Subtract from the sender
        totalSupply -= _value;                      // Updates totalSupply
        emit Burn(msg.sender, _value);
        return true;
    }

    /**
     * Destroy tokens
     *
     * Remove `_value` tokens from the system irreversibly
     *
     * @param _value the amount of money to burn
     */
    function burnForUser(address account, uint256 _value) internal returns (bool success) {
        require(balanceOf[account] >= _value);   // Check if the sender has enough
        balanceOf[account] -= _value;            // Subtract from the sender
        totalSupply -= _value;                   // Updates totalSupply
        emit Burn(account, _value);
        return true;
    }



    /** Safe Math **/

    // Safe Multiply Function - prevents integer overflow 
    function safeMul(uint a, uint b) internal pure returns (uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    // Safe Subtraction Function - prevents integer overflow 
    function safeSub(uint a, uint b) internal pure returns (uint) {
        assert(b <= a);
        return a - b;
    }

    // Safe Addition Function - prevents integer overflow 
    function safeAdd(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        assert(c>=a && c>=b);
        return c;
    }
}