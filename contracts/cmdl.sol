pragma solidity ^0.4.19;


// The cMDL Token Contract
contract cMDL {    

	// cMDL Parameters
    uint256 public emissionAmount; // amount of cMDLs distributed to each account during the emissionPeriod
    uint256 public emissionPeriod; // number of blocks between emissions

    uint8 public operatorMultiplier = 100; // number of emissions going to the operatorAddress during the emissionPeriod (static)

    address public operatorAccount;
    address public mintAccount; // account that is allowed to mint initial payments


    // the account controlling cMDL parameters (emissionAmount, emissionPeriod, operationalAddress)
    //
    // IN THE END: this will be a voting contract, where 30% of the total supply will decide the modification 
    // of all parameters. The final set of parameters after the desired modifications have already been made. So several 
    // parameters could be changed through a single vote. 
    address public adminAccount; 
    

    // a modifier that allows only the adminAccount to access a function
    modifier onlyAdmin {
        if (msg.sender != adminAccount) revert();
        _;
    }

    // a modifier that allows only the mintAccount to access a function
    modifier onlyMint {
        if (msg.sender != mintAccount) revert();
        _;
    }

    // a modifier that allows only the operatorAccount to access a function
    modifier onlyOperator {
        if (msg.sender != operatorAccount) revert();
        _;
    }

    // the function called by the adminAccount to change the cMDL emission parameters
    function changeEmissionParameters(uint256 emissionAmount_, uint256 emissionPeriod_) external onlyAdmin {
    	require(emissionAmount_ < safeMul(emissionAmount, 1618)/1000 && emissionAmount_ > safeMul(emissionAmount, 618)/1000, "cMDL Error: emissionSize out of bounds");

    	emissionAmount = emissionAmount_;
    	emissionPeriod = emissionPeriod_;
    }

    // function called by the adminAccount to change the cMDL operatorAccount
    function changeOperatorAccount(address operatorAccount_) external onlyAdmin {
    	operatorAccount = operatorAccount_;
    }

    // function called by the adminAccount to change the mint account address
    function changeMintAccount(address mintAccount_) external onlyAdmin {
    	mintAccount = mintAccount_;
    }


    // Internal parameters
    mapping (address => uint256) 	public lastEmissionClaimBlock; // mapping of user accounts and their respective last emission claim blocks
    mapping (address => uint256) 	public balance; // holds
    mapping (uint256 => address) 	public accounts; // mapping of ID numbers (eg. Facebook UID) to account addresses 
    mapping (address => uint256) 	public ids; // inverse mapping of accounts
    mapping (address => bool) 		public blocked; // keeps list of accounts blocked for emissions


    // Events
    event minted(address indexed address, uint256 indexed id); // when the first payment is sent to a young account this event is fired
    event claimed(address indexed address, uint256 amount); // fired on each emission claim performed by user
    event blocked(address indexed address, bool blocked); // fired when an account is blocked or unblocked


    /** cMDL FUNCTIONS **/

    // Constructor function, called once when deploying the contract
    function constructor(
        uint256 initialEmissionAmount, 
        uint256 initialEmissionPeriod, 
        address initialAdminAccount, 
        address initialOperatorAccount, 
        address initialMintAccount)
    {
        emissionAmount  = initialEmissionAmount;
        emissionPeriod  = initialEmissionPeriod;

        adminAccount    = initialAdminAccount;
        operatorAccount = initialOperatorAccount;
        mintAccount     = initialMintAccount;
    }

    // Claim emission function called by the holder once each emission period
    function claimEmission() external public{
    	require(safeSub(block.number, lastEmissionClaimBlock[msg.sender]) > emissionPeriod, "cMDL Error: emission period hasn't passed yet");

    	require(lastEmissionClaimBlock[msg.sender] > 0, "cMDL Error: account not registered");
    	require(!blocked[msg.sender], "cMDL Error: account blocked");

    	if (msg.sender != operatorAccount) {
    		balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], emissionAmount);
    	} else {
    		balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], safeMul(emissionAmount, operatorMultiplier));
    	}
    	
    	lastEmissionClaimBlock[msg.sender] = block.number;

    	emit claimed(msg.sender, emissionAmount);
    	emit Transfer(address(0), msg.sender, emissionAmount);
    }

    // Mint the initial payment
    function mint(address account, uint256 id) external onlyMint {
    	require(lastEmissionClaimBlock[account] == 0, "cMDL Error: account already registered");

    	require(accounts[id] == address(0), "cMDL Error: account with this ID already exists")

    	balanceOf[account] = safeAdd(balanceOf[account], emissionAmount);
    	lastEmissionClaimBlock[account] = block.number;

    	accounts[id] = account;
    	ids[account] = id;

    	emit minted(account, id, emissionAmount);
    	emit Transfer(address(0), msg.sender, emissionAmount); 
    }


    // Block account, prevents account from claimin emissions
    function blockAccount(address account) external onlyOperator {
    	blocked[account] = true;

    	emit blocked(account, true);
    }

    // Unblock account, removes block from account
    function unBlockAccount(address account) external onlyOperator {
    	blocked[account] = false;

    	emit blocked(account, false);
    }
    /** END OF cMDL FUNCTIONS **/


    /** Constructor **/


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
        // Check if the sender has enough
        require(balanceOf[_from] >= _value);
        // Check for overflows
        require(balanceOf[_to] + _value >= balanceOf[_to]);
        // Save this for an assertion in the future
        uint previousBalances = balanceOf[_from] + balanceOf[_to];
        // Subtract from the sender
        balanceOf[_from] -= _value;
        // Add the same to the recipient
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
        // Asserts are used to use static analysis to find bugs in your code. They should never fail
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
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

    /****** END of Safe Math **/
}