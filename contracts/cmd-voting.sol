pragma solidity ^0.4.19;

/* Interface for cMDL contract */
contract cMDL {

    // ERC20 interface
    bytes32 public name;
    bytes32 public symbol;
    uint256 public totalSupply;
    uint8 public decimals;

    function burn(uint256 _value) public returns (bool success);



    // Core Parameters
    uint256 public emissionAmount; // amount of cMDLs distributed to each account during the emissionPeriod
    uint256 public emissionPeriod; // number of blocks between emissions
    uint256 public proposalFee; // fee paid to submit a votting proposal

    uint8 public operatorMultiplier; // number of emissions going to the operatorAddress during the emissionPeriod (static)

    address public operatorAccount; // account that changes the mintAccount and can block/unblock accounts, operator account also distributes ETH to all accounts to allow for free transfers
    address public mintAccount; // account that is allowed to mint initial payments

    mapping (address => uint256)    public lastEmissionClaimBlock; // mapping of user accounts and their respective last emission claim blocks
    mapping (address => uint256)    public balance; // holds
    mapping (uint256 => address)    public accounts; // mapping of ID numbers (eg. Facebook UID) to account addresses 
    mapping (address => uint256)    public ids; // inverse mapping of accounts
    mapping (address => bool)       public blocked; // keeps list of accounts blocked for emissions
    mapping (address => bool)       public wasOperator; // keeps list of past operator accounts

    uint256 public active; // number of active (voting) accounts

    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    
    function changeEmissionParameters(uint256 newEmissionAmount, uint256 newEmissionPeriod);
    function changeOperatorAccount(address newOperatorAccount);
    function changeVotingContract(address newVotingContract);
    function changeProposalFee(uint256 newProposalFee);
    function changeOperatorMultiplier(uint8 newOperatorMultiplier);




    // Taxation
    uint256 public maxTaxProportion; // the maximum tax proportion
    uint256 public taxProportion; // the tax proportion deducted from each emission (1 = 1e18, 0.05 = 5e16 etc)
    address public taxAccount; // the account collecting the tax

    function changeTaxProportion(uint256 newTaxProportion);
    function changeTaxAccount(address newTaxAccount);





    // Transaction fees
    uint256 public maxTxFee; // maximum transaction fee
    uint256 public txFee; // the transaction fee proportion deducted from each cMDL transfer (1 = 1e18, 0.001 (0.1%) = 1e15 etc)
    address public txFeeAccount; // the account collecting the transaction fee

    function changeTxFee(uint256 newTxFee);
    function changeTaxFeeAccount(address newTxFeeAccount);




}


// The cMDL Admin Contract v1
// A voting contract that allows modification of the cMDL parameters
contract cMDL_Admin_v1 {

    // Votting parameters
    uint8 minimumVoteParticipation = 30; // minimum number of voters for the proposal to pass
    uint8 minimumYaysToPass = 51; // minimum proportion of yays to pass a change from the total number of voters

    mapping(bytes32 => bool) votes; // holds all the votes made by the users

    enum ProposalType {
        /*  0 */EMISSION_PARAMETERS,                 
        /*  1 */OPERATOR_ACCOUNT,                
        /*  2 */VOTING_CONTRACT,       
        /*  3 */TAX_PROPORTION,
        /*  4 */TAX_ACCOUNT,
        /*  5 */TX_FEE,
        /*  6 */TX_FEE_ACCOUNT
    }

    /** Helper functions **/
    // validates vote execution
    function validateVotePeriod(uint256 votePeriod)
    {
        require (votePeriod < maxVotePeriod, 'cMDL_Admin Error: votePeriod cannot be higher than maxVotePeriod');
    }

    function validateVote(uint256 expires, uint256 yays, uint256 nays)
    {
        require(emissionParamsProposals[proposalHash].expires > 0, "cMDL_Admin Error: Proposal not found");
        require(emissionParamsProposals[proposalHash].expires < block.number, "cMDL_Admin Error: Proposal not expired");

        require(safeMul(yays, 100) > nays, "cMDL_Admin Error: number of yays to small");

        uint256 percentVoted = safeMul(safeAdd(yays, nays), 100) / cMDL(cmdlContract).active;
        require(percentVoted > minimumVoteParticipation, "cMDL_Admin Error: minimum participation not reached");

        uint256 percentYays = safeMul(yays, 100) / safeAdd(yays, nays);
        require(percentYays >= minimumYaysToPass, "cMDL_Admin Error: minimum yays not passed");
    }



    


    /** Emission Parameters Vote **/
    struct EmmissionParamsProposal {
        uint256 emissionAmount,
        uint256 emissionPeriod,
        uint256 exipires, // the block number when the vote will expire
        uint256 votes_yay, // number of accounts that have voted for the proposal
        uint256 votes_nay // number of accounts that have voted against the proposal
    }

    mapping(bytes32 => EmmissionParamsProposal) emissionParamsProposals; // mapping with emission parameter proposals


    event emissionParamsVoteInitiated(bytes32 indexed proposalHash, address indexed account, uint256 proposedEmissionAmount, uint256 proposedEmissionPeriod, uint256 expires);
    event emissionParamsChangeVoteCast(bytes32 indexed proposalHash, bool vote);
    event emissionParametersUpdated(bytes32 indexed proposalHash, uint256 newEmissionAmount, uint256 newEmissionPeriod);

    function createEmissionParamsProposal(uint256 proposedEmissionAmount, uint256 proposedEmissionPeriod, uint256 votePeriod) external
    {   
        validateVotePeriod(votePeriod);

        uint256 expires = safeAdd(block.number, votePeriod);
        bytes32 proposalHash = keccak256(this, msg.sender, ProposalType.EMISSION_PARAMETERS, proposedEmissionAmount, proposedEmissionPeriod, expires);

        cMDL(cmdlContract).chargeUserForProposal(msg.sender);

        emissionParamsProposals[proposalHash] = new EmmissionParamsProposal({
            emissionAmount     : proposedEmissionAmount,
            emissionPeriod     : proposedEmissionPeriod,
            exipires           : expires,
            voted              : 0    
        });

        emit emissionParamsVoteInitiated(proposalHash, msg.sender, proposedEmissionAmount, proposedEmissionPeriod, expires);
    }    

    function voteEmissionParamsChange(bytes32 proposalHash, bool vote) public external returns (bool success)
    {
        bytes32 voteHash = keccak256(this, msg.sender, proposalHash);
        require(!votes[voteHash], "cMDL_Admin Error: Vote on this proposal already casted");
        require(emissionParamsProposals[proposalHash].expires > 0, "cMDL_Admin Error: Proposal not found");

        votes[voteHash] = true;

        if (vote) {
            emissionParamsProposals[proposalHash].votes_yay = safeAdd(emissionParamsProposals[proposalHash].votes_yay, 1);
        } else {
            emissionParamsProposals[proposalHash].votes_nay = safeAdd(emissionParamsProposals[proposalHash].votes_nay, 1);
        }
        
        emit emissionParamsChangeVoteCast(proposalHash, vote);
    }

    function executeEmissionParamsProposal(bytes32 proposalHash) public external 
    {
        validateVote(emissionParamsProposals[proposalHash].expires, emissionParamsProposals[proposalHash].votes_yay, emissionParamsProposals[proposalHash].votes_nay);

        cMDL(cmdlContract).changeEmissionParameters(emissionParamsProposals[proposalHash].emissionAmount, emissionParamsProposals[proposalHash].emissionPeriod);
        
        emit emissionParametersUpdated(proposalHash, emissionParamsProposals[proposalHash].emissionAmount, emissionParamsProposals[proposalHash].emissionPeriod);
    }










    /** Change account vote (operator, votingContract, taxAccount, txFeeAccount) **/
    struct AddressChangeProposal {
        address newAccount; // the proposed new account
        uint8 proposalType; // the proposal type (operator, votingContract, taxAccount, txFeeAccount)
        uint256 exipires, // the block number when the vote will expire
        uint256 votes_yay, // number of accounts that have voted for the proposal
        uint256 votes_nay // number of accounts that have voted against the proposal
    }

    mapping(bytes32 => AddressChangeProposal) AddressChangeProposals; // mapping with address change proposals


    event accountChangeVoteInitiated(bytes32 indexed proposalHash, address indexed account, uint8 proposalType, address newAccount, uint256 expires);
    event accountChangeVoteCast(bytes32 indexed proposalHash, bool vote);
    event accountUpdated(bytes32 indexed proposalHash, uint8 proposalType, address newAccount);

    function createAddressChangeProposal(uint8 proposalType, address newAccount, uint256 votePeriod) external
    {   
        validateVotePeriod(votePeriod);

        uint256 expires = safeAdd(block.number, votePeriod);
        bytes32 proposalHash = keccak256(this, msg.sender, proposalType, newAccount, expires);

        cMDL(cmdlContract).chargeUserForProposal(msg.sender);

        AddressChangeProposals[proposalHash] = new AddressChangeProposal({
            newAccount     : newAccount,
            proposalType   : proposalType,
            exipires       : expires,
            voted          : 0    
        });

        emit accountChangeVoteInitiated(proposalHash, msg.sender, proposalType, newAccount, expires);
    }    

    function voteAccountChange(bytes32 proposalHash, bool vote) public external
    {
        bytes32 voteHash = keccak256(this, msg.sender, proposalHash);
        require(!votes[voteHash], "cMDL_Admin Error: Vote on this proposal already casted");
        require(AddressChangeProposals[proposalHash].expires > 0, "cMDL_Admin Error: Proposal not found");

        votes[voteHash] = true;

        if (vote) {
            AddressChangeProposals[proposalHash].votes_yay = safeAdd(AddressChangeProposals[proposalHash].votes_yay, 1);
        } else {
            AddressChangeProposals[proposalHash].votes_nay = safeAdd(AddressChangeProposals[proposalHash].votes_nay, 1);
        }
        
        emit accountChangeVoteCast(proposalHash, vote);
    }

    function executeAccountChangeProposal(bytes32 proposalHash) public external 
    {
        validateVote(AddressChangeProposals[proposalHash].expires, AddressChangeProposals[proposalHash].votes_yay, AddressChangeProposals[proposalHash].votes_nay);


        if (AddressChangeProposals[proposalHash].proposalType == uint8(ProposalType.OPERATOR_ACCOUNT)) {
            cMDL(cmdlContract).changeOperatorAccount(AddressChangeProposals[proposalHash].newAccount);
        } else if (AddressChangeProposals[proposalHash].proposalType == uint8(ProposalType.VOTING_CONTRACT)) {
            cMDL(cmdlContract).changeVotingContract(AddressChangeProposals[proposalHash].newAccount);
        } else if (AddressChangeProposals[proposalHash].proposalType == uint8(ProposalType.TAX_ACCOUNT)) {
            cMDL(cmdlContract).changeTaxAccount(AddressChangeProposals[proposalHash].newAccount);
        } else if (AddressChangeProposals[proposalHash].proposalType == uint8(ProposalType.TX_FEE_ACCOUNT)) {
            cMDL(cmdlContract).changeTaxFeeAccount(AddressChangeProposals[proposalHash].newAccount);
        } else {
            revert();
        }       
        
        
        emit accountUpdated(proposalHash, AddressChangeProposals[proposalHash].proposalType, AddressChangeProposals[proposalHash].newAccount);
    }













    /** Change parameter vote (txFee and taxProportion) **/
    struct NumberChangeProposal {
        uint256 newValue; // the proposed new value
        uint8 proposalType; // the proposal type (operator, votingContract, taxAccount, txFeeAccount)
        uint256 exipires, // the block number when the vote will expire
        uint256 votes_yay, // number of accounts that have voted for the proposal
        uint256 votes_nay // number of accounts that have voted against the proposal
    }

    mapping(bytes32 => NumberChangeProposal) NumberChangeProposals; // mapping with address change proposals


    event numberChangeVoteInitiated(bytes32 indexed proposalHash, address indexed account, uint8 proposalType, uint256 newValue, uint256 expires);
    event numberChangeVoteCast(bytes32 indexed proposalHash, bool vote);
    event numberUpdated(bytes32 indexed proposalHash, uint8 proposalType, address newAccount);

    function createNumberChangeProposal(uint8 proposalType, uint256 newValue, uint256 votePeriod) external
    {   
        validateVotePeriod(votePeriod);

        uint256 expires = safeAdd(block.number, votePeriod);
        bytes32 proposalHash = keccak256(this, msg.sender, proposalType, newValue, expires);

        cMDL(cmdlContract).chargeUserForProposal(msg.sender);

        NumberChangeProposals[proposalHash] = new NumberChangeProposal({
            newValue       : newValue,
            proposalType   : proposalType,
            exipires       : expires,
            voted          : 0    
        });

        emit numberChangeVoteInitiated(proposalHash, msg.sender, proposalType, newValue, expires);
    }    

    function voteNumberChange(bytes32 proposalHash, bool vote) public external
    {
        bytes32 voteHash = keccak256(this, msg.sender, proposalHash);
        require(!votes[voteHash], "cMDL_Admin Error: Vote on this proposal already casted");
        require(NumberChangeProposals[proposalHash].expires > 0, "cMDL_Admin Error: Proposal not found");

        votes[voteHash] = true;

        if (vote) {
            NumberChangeProposals[proposalHash].votes_yay = safeAdd(NumberChangeProposals[proposalHash].votes_yay, 1);
        } else {
            NumberChangeProposals[proposalHash].votes_nay = safeAdd(NumberChangeProposals[proposalHash].votes_nay, 1);
        }
        
        emit numberChangeVoteCast(proposalHash, vote);
    }

    function executeNumberChangeProposal(bytes32 proposalHash) public external 
    {
        validateVote(NumberChangeProposals[proposalHash].expires, NumberChangeProposals[proposalHash].votes_yay, NumberChangeProposals[proposalHash].votes_nay);

        if (NumberChangeProposals[proposalHash].proposalType == uint8(ProposalType.TAX_PROPORTION)) {
            cMDL(cmdlContract).changeTaxProportion(NumberChangeProposals[proposalHash].newValue);
        } else if (NumberChangeProposals[proposalHash].proposalType == uint8(ProposalType.TX_FEE)) {
            cMDL(cmdlContract).changeTxFee(NumberChangeProposals[proposalHash].newValue);
        } else {
            revert();
        }              
        
        emit numberUpdated(proposalHash, NumberChangeProposals[proposalHash].proposalType, NumberChangeProposals[proposalHash].newValue);
    }   











	/**  Voting contract core parameters **/
    address public cmdlContract;
    address public owner;

    uint256 public maxVotePeriod; // the number of blocks for which a proposal can be votted upon
    

    /** Admin contract managamenent functions **/
    // sets the cMDL contract address, used once after deployment
    function setCmdlContract(address cmdContract_) external onlyOwner {
        require(cmdlContract == address(0), 'cMDL_Admin Error: cmdlContract already set');
        cmdlContract = cmdlContract_;
    }

    // changes contract owner
    event ownerChanged(address indexed newOwner);
    function setOwner(address owner_) external onlyOwner {
        owner = owner_;
        ownerChanged(owner);
    }

    /** Override functions 
     ** This actions allow access to the cMDL contract parameters to the "owner" without votting.
     ** Once the functionality of the votting system is fully tested, the owner account will be set
     ** to the Zero account (0x0000000000000000000000000000000000000000) which cannot be used by anyone
     ** and the overide functions will no longer be accessed.
     **/
    function override_changeEmissionParameters(uint256 emissionAmount_, uint256 emissionPeriod_) external onlyOwner {
        cMDL(cmdlContract).changeEmissionParameters(emissionAmount_, emissionPeriod_);
    }

    function override_changeOperatorAccount(address operatorAccount_) external onlyOwner {
        cMDL(cmdlContract).changeOperatorAccount(operatorAccount_);
    }

    function override_changeMintAccount(address mintAccount_) external onlyOwner {
        cMDL(cmdlContract).changeMintAccount(mintAccount_);
    }

    function override_changeTaxProportion(uint256 taxProportion_) external onlyOwner {
        cMDL(cmdlContract).changeTaxProportion(taxProportion_);
    }

    function override_changeTaxAccount(address taxAccount_) external onlyOwner {
        cMDL(cmdlContract).changeTaxAccount(taxAccount_);
    }

    function override_changeTxFee(uint256 txFee_) external onlyOwner {
        cMDL(cmdlContract).changeTxFee(txFee_);
    }

    function override_changeTaxFeeAccount(address txFeeAccount_) external onlyOwner {
        cMDL(cmdlContract).changeTaxFeeAccount(txFeeAccount_);
    }

    function override_changeAdminAccount(address adminAccount_) external onlyOwner {
        cMDL(cmdlContract).changeAdminAccount(adminAccount_);
    }


    /** Modifiers **/
    // a modifier that allows only the adminAccount to access a function
    modifier onlyOwner {
        if (msg.sender != owner) revert();
        _;
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