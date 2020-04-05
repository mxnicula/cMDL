pragma solidity ^0.4.19;


// The cMDL Token Contract
contract cMDL_v1 {    

	// Core Parameters
    uint256 public emissionAmount; // amount of cMDLs distributed to each account during the emissionPeriod
    uint256 public emissionPeriod; // number of blocks between emissions
    uint256 public proposalFee; // fee paid to submit a votting proposal in order to change emission parameters

    uint8 public inactivityPeriods = 4; // number of claims missed before an account can be marked as inactive

    uint8 public operatorMultiplier = 10; // number of emissions going to the operatorAddress during the emissionPeriod (static)
    uint8 public maxOperatorMultiplier = 1000; // maximum value for the operatorMultiplier

    address public operatorAccount; // account that changes the mintAccount and can block/unblock accounts, operator account also distributes Rinkeby ETH to all accounts to allow for free transfers
    address public mintAccount; // account that is allowed to mint initial payments
    
    // the account controlling cMDL parameters 
    address public votingContracnt; 







    /** Emission Functionality **/  
    // Internal parameters
    mapping (address => uint256)    public lastEmissionClaimBlock; // mapping of user accounts and their respective last emission claim blocks
    mapping (address => uint256)    public balance; // holds
    mapping (uint256 => address)    public accounts; // mapping of ID numbers (eg. Facebook UID) to account addresses 
    mapping (address => uint256)    public ids; // inverse mapping of accounts
    mapping (address => bool)       public blocked; // keeps list of accounts blocked for emissions
    mapping (address => bool)       public inactive; // mapping of inactive accounts, an account can be set as inactive if it doesn't claim the emission for more than 4 consecutive emission periods
    mapping (address => uint256)    public votes; // mapping of aaccounts to number of votes delegated

    uint256 public active; // number of active (voting) accounts


    // Events
    event minted(address indexed address, uint256 indexed id); // when the first payment is sent to a young account this event is fired
    event claimed(address indexed address, uint256 amount); // fired on each emission claim performed by user
    event blocked(address indexed address, bool blocked); // fired when an account is blocked or unblocked
    event setInactive(address account); // fired when an account is marked as inactive


    // Claim emission function called by the holder once each emission period
    function claimEmission() external public {
    	require(safeSub(block.number, lastEmissionClaimBlock[msg.sender]) > emissionPeriod, "cMDL Error: emission period did not pass yet");

    	require(lastEmissionClaimBlock[msg.sender] > 0, "cMDL Error: account not registered");
    	require(!blocked[msg.sender], "cMDL Error: account blocked");

        uint256 taxAmount = safeMul(emissionAmount, taxProportion)/1e18;
        uint256 netAmount = safeSub(emissionAmount, taxAmount);

    	if (msg.sender != operatorAccount) {
    		balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], netAmount);
            balanceOf[taxAccount] = safeAdd(balanceOf[taxAccount], taxAmount);

            emit Transfer(address(0), taxAccount, taxAmount);
    	} else {
            balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], safeMul(netAmount, operatorMultiplier));
    		balanceOf[taxAccount] = safeAdd(balanceOf[taxAccount], safeMul(taxAmount, operatorMultiplier));

            emit Transfer(address(0), taxAccount, safeMul(taxAmount, operatorMultiplier));
    	}
    	
    	lastEmissionClaimBlock[msg.sender] = block.number;
        totalSupply = safeAdd(totalSupply, emissionAmount);

        if (inactive[account])
        {
            setActive(account);
        }

    	emit claimed(msg.sender, emissionAmount);
    	emit Transfer(address(0), msg.sender, emissionAmount);
    }

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

    	emit minted(account, id, emissionAmount);
        emit Transfer(address(0), msg.sender, emissionAmount); 
    	emit Transfer(address(0), taxAccount, taxAmount); 
    }


    // Block account, prevents account from claimin emissions
    function blockAccount(address account) external onlyOperator {
    	blocked[account] = true;

        active = safeSub(active, 1);

    	emit blocked(account, true);
    }

    // Unblock account, removes block from account
    function unBlockAccount(address account) external onlyOperator {
    	blocked[account] = false;

        active = safeAdd(active, 1);

    	emit blocked(account, false);
    }

    // Set an account as inactive
    function setInactive(address account) external onlyMint {
        require(lastEmissionClaimBlock[account] < safeSub(block.number, safeMul(emissionPeriod, inactivityPeriods)), "cMDL Error: account was active during the active period");
        require(lastEmissionClaimBlock[account] > 0, "cMDL Error: account not registered");

        inactive[account] = true;
        active = safeSub(active, 1);

        setInactive(account);
    }

    // Sets account as active and increases the number of active accounts (registered)
    // can only be called from the claim function
    function setActive(address account) internal {
        inactive[account] = false;
        active = safeAdd(active, 1);
    }










    /** Parameter Functionality **/    
    // Parameter Events
    event emissionParametersChanged(uint256 newEmissionAmount, uint256 newEmissionPeriod); // fired when emission parameters are changed
    event operatorChanged(address indexed newOperatorAccount); // fired when operatorAccount is modified
    event mintAccountChanged(address indexed newMintAccount); // fired when mint account is changed
    event votingContractChanged(address indexed newVotingContract); // fired when mint account is changed
    event proposalFeeChanged(uint256 newProposalFee); // fired when the proposal fee is changed
    event chargedProposalFee(address indexed account, uint256 fee); // fired when a proposal fee is charged
    event operatorMultiplierChanged()

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

    // function called by the votingContract to charge the user for creating a proposal
    function chargeUserForProposal(address account) external onlyVote  {
        require(balanceOf[account] >= proposalFee, "cMDL Error: user balance cannot cover the proposal fee");

        burnForUser(account, proposalFee);

        emit chargedProposalFee(account, proposalFee);
    }

    // function called by the votingContract to change the proposal fee
    function changeProposalFee(uint256 proposalFee_) external onlyVote {
        require(proposalFee_ < safeMul(emissionAmount, 100), "cMDL Error: proposal fee cannot be higher than 10 emissions" );

        proposalFee = proposalFee_;

        emit proposalFeeChanged(proposalFee_);
    }

    // function called by the votingContract to change the proposal fee
    function changeOperatorMultiplier(uint8 newOperatorMultiplier) external onlyVote {
        require(newOperatorMultiplier < maxOperatorMultiplier && newOperatorMultiplier > 0, "cMDL Error: multiplier out of range" );

        operatorMultiplier = newOperatorMultiplier;

        emit operatorMultiplierChanged(operatorMultiplier);
    }














    /** Taxation Functionality **/
    // Tax account is an account that can collect a share from every emission (up to 5% of the emission value)
    // The tax account can be further decentralized by making it a smart contract that can distribute the collected 
    // taxes further to other accounts that can also be smart contracts
    uint256 public maxTaxProportion; // the maximum tax proportion
    uint256 public taxProportion; // the tax proportion deducted from each emission (1 = 1e18, 0.05 = 5e16 etc)
    address public taxAccount; // the account collecting the tax

    event taxProportionChanged(uint256 newTaxPercent); // fired when the taxProportion is changed
    event taxAccountChanged(address newTaxAccount); // fired when the taxAccount is modified

    // the function called by the votingContract to change the tax proportion
    function changeTaxProportion(uint256 taxProportion_) external onlyVote {
        require(taxProportion < maxTaxProportion, "cMDL Error: taxPercent cannot be higher than maxTaxProportion");

        taxProportion = taxProportion_;
        emit taxProportionChanged(taxProportion);
    }

    // the function called by the votingContract to change the taxAccount
    function changeTaxAccount(address taxAccount_) external onlyVote {
        taxAccount = taxAccount_;

        emit taxAccountChanged(taxAccount);
    }













    /** Transaction Fee Functionality **/
    // Transaction fee account is the account receiving the transaction fee from each cMDL transfer
    // This functionality is optional to mitigate network congestion that could lead to high network fees
    // Can also be used to collect additional taxes from users
    // Transaction fee is paid by the receiver
    uint256 public maxTxFee; // maximum transaction fee
    uint256 public txFee; // the transaction fee proportion deducted from each cMDL transfer (1 = 1e18, 0.001 (0.1%) = 1e15 etc)
    address public txFeeAccount; // the account collecting the transaction fee

    event txFeeChanged(uint256 newTxFee); // fired when the taxProportion is changed
    event txFeeAccountChanged(address newTxFeeAccount); // fired when the taxAccount is modified

    // the function called by the votingContract to change the txFee
    function changeTxFee(uint256 txFee_) external onlyVote {
        require(txFee_ < maxTxFee, "cMDL Error: txFee cannot be higher than maxTxFee");

        txFee = txFee_;
        emit txFeeChanged(txFee);
        return true;
    }

    // the function called by the votingContract to change the txFeeAccount
    function changeTaxFeeAccount(address txFeeAccount_) external onlyVote {
        txFeeAccount = txFeeAccount_;

        emit txFeeAccountChanged(txFeeAccount);
    }










    /** Transaction Burn Fee Functionality **/
    // Transaction burn fee is the fee taken during each transfer from the transferred amount and burnt.
    // This is necessary to combat inflation, through the burn fee, the total supply of cMDL is decreased 
    // as the transferred volume increases
    uint256 public burnFee; // the burn fee proportion deducted from each cMDL transfer (1 = 1e18, 0.001 (0.1%) = 1e15 etc)

    event burnFeeChanged(uint256 newBurnFee); // fired when the burnFee is changed

    // the function called by the operatorAccount to change the burnFee
    function changeBurnFee(uint256 burnFee_) external onlyOperator {
        require(burnFee_ < 5e16, "cMDL Error: burn fee cannot be higher than 5%");

        burnFee = burnFee_;
        emit burnFeeChanged(burnFee);
    }











    /** Internal Functionality **/

    /** Constructor **/
    // Constructor function, called once when deploying the contract
    function constructor(
        string name_,
        string symbol_,

        uint256 maxTaxProportion_,
        uint256 maxTxFee_,

        uint256 initialEmissionAmount, 
        uint256 initialEmissionPeriod, 
        uint256 initialTaxProportion,
        uint256 initialTxFee,
        uint256 initialBurnFee,

        address initialVotingContract, 
        address initialOperatorAccount, 
        address initialMintAccount,
        address initialTaxAccount,
        address initialTxFeeAccount
    )
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

        votingContracnt = initialVotingContract;
        operatorAccount = initialOperatorAccount;
        mintAccount     = initialMintAccount;
        taxAccount      = initialTaxAccount;
        txFeeAccount    = initialTxFeeAccount;
    }




    /** Modifiers **/
    // a modifier that allows only the votingContract to access a function
    modifier onlyVote {
        require(msg.sender == votingContracnt, "cMDL Error: accesses denied");
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
        balanceOf[_from] = safeSub(balanceOf[_from], safeAdd(_value, txFeeAmount));
        balanceOf[_to] = safeAdd(balanceOf[_to], _value);
        burnForUser(_to, burnFeeAmount);
        
        balanceOf[txFeeAccount] = safeAdd(balanceOf[txFeeAccount], txFeeAmount);

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