// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "./VotingToken.sol";
import "./interfaces/IGovernance.sol";

// ============ GOVERNANCE CONTRACT ============

/// @title Governance
/// @notice Handles proposal creation, voting, and execution for the VoteStake protocol
contract Governance is Ownable {
    
    // ============ ENUMS ============
    
    /// @notice Possible states of a proposal
    enum ProposalState { ACTIVE, DEFEATED, SUCCEEDED, EXECUTED, CANCELLED }
    
    /// @notice Types of actions that can be executed
    enum ActionType { SET_APY, CHANGE_PENALTY, CUSTOM_ACTION }
    
    // ============ STRUCTS ============
    
    /// @notice Data structure representing a governance proposal
    struct Proposal {
        uint256 id;                          // Unique proposal ID
        address proposer;                    // Address of proposal creator
        string description;                  // Proposal description
        ActionType actionType;               // Type of action to execute
        uint256 actionValue;                 // Parameter value to change (e.g., new APY)
        uint256 startBlock;                  // Block where voting starts
        uint256 endBlock;                    // Block where voting ends
        uint256 votesFor;                    // Number of votes in favor
        uint256 votesAgainst;                // Number of votes against
        uint256 votingSnapshotId;            // Snapshot ID to freeze voting power
        ProposalState state;                 // Current proposal state
        bool executed;                       // Whether proposal has been executed
        mapping(address => bool) hasVoted;   // Tracks who has voted
        mapping(address => bool) voteChoice; // Vote choice mapping (true = favor, false = against)
    }
    
    // ============ STATE VARIABLES ============
    
    address public votingTokenAddress;       // VotingToken contract address
    address public voteStakeAddress;         // VoteStake contract address
    
    uint256 public proposalCounter = 0;      // Proposal counter
    uint256 public votingPeriod = 45818;     // Voting duration (~3 days on Ethereum)
    uint256 public minProposalVotes = 10e18; // Minimum tokens required to create proposal
    uint256 public quorumPercent = 5000;     // 50% quorum required (basis points)
    uint256 public majorityPercent = 5000;   // 50% majority required (basis points)
    
    mapping(uint256 => Proposal) public proposals;   // Mapping of proposals by ID
    uint256[] public proposalIds;                    // Array of all proposal IDs
    
    // ============ EVENTS ============
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        ActionType actionType,
        uint256 actionValue
    );
    
    event VoteCasted(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );
    
    event ProposalFinalized(
        uint256 indexed proposalId,
        ProposalState finalState,
        uint256 votesFor,
        uint256 votesAgainst
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId,
        ActionType actionType,
        uint256 actionValue
    );
    
    event VotingPeriodChanged(uint256 newPeriod);
    event MinProposalVotesChanged(uint256 newMin);
    event QuorumPercentChanged(uint256 newQuorum);
    
    // ============ CONSTRUCTOR ============
    
    /// @notice Initialize the Governance contract
    /// @param _votingToken Address of the VotingToken contract
    /// @param _voteStake Address of the VoteStake contract
    constructor(address _votingToken, address _voteStake) Ownable(msg.sender) {
        require(_votingToken != address(0), "Invalid voting token");
        require(_voteStake != address(0), "Invalid VoteStake");
        
        votingTokenAddress = _votingToken;
        voteStakeAddress = _voteStake;
    }
    
    // ============ CREATE PROPOSAL ============
    
    /// @notice Create a new governance proposal
    /// @param description Description of the proposal
    /// @param actionType Type of action to execute
    /// @param actionValue Parameter value to change
    /// @return proposalId ID of the created proposal
    function createProposal(
        string memory description,
        ActionType actionType,
        uint256 actionValue
    ) external returns (uint256) {
        // Validate inputs
        require(bytes(description).length > 0, "Empty description");
        require(
            IVotingToken(votingTokenAddress).getPastVotes(msg.sender, block.number - 1) >= minProposalVotes,
            "Insufficient voting power to propose"
        );
        
        // Create snapshot to freeze voting power
        uint256 snapshotId = IVotingToken(votingTokenAddress).snapshot();
        
        // Get proposal ID
        uint256 proposalId = proposalCounter++;
        
        // Create proposal structure
        Proposal storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.description = description;
        newProposal.actionType = actionType;
        newProposal.actionValue = actionValue;
        newProposal.startBlock = block.number;
        newProposal.endBlock = block.number + votingPeriod;
        newProposal.votesFor = 0;
        newProposal.votesAgainst = 0;
        newProposal.votingSnapshotId = snapshotId;
        newProposal.state = ProposalState.ACTIVE;
        newProposal.executed = false;
        
        // Store in array
        proposalIds.push(proposalId);
        
        emit ProposalCreated(proposalId, msg.sender, description, actionType, actionValue);
        
        return proposalId;
    }
    
    // ============ VOTING ============
    
    /// @notice Cast a vote on an active proposal
    /// @param proposalId ID of the proposal
    /// @param support true = in favor, false = against
    function castVote(uint256 proposalId, bool support) external {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        
        Proposal storage proposal = proposals[proposalId];
        
        // Validate proposal is active
        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");
        require(block.number <= proposal.endBlock, "Voting period ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        // Get frozen voting power from snapshot
        uint256 votingPower = IVotingToken(votingTokenAddress).getPastVotes(
            msg.sender,
            proposal.startBlock
        );
        
        require(votingPower > 0, "No voting power");
        
        // Count vote
        if (support) {
            proposal.votesFor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }
        
        // Mark that user has voted
        proposal.hasVoted[msg.sender] = true;
        proposal.voteChoice[msg.sender] = support;
        
        emit VoteCasted(proposalId, msg.sender, support, votingPower);
    }
    
    // ============ FINALIZE VOTING ============
    
    /// @notice Finalize voting and determine the result
    /// @param proposalId ID of the proposal
    function finalizeProposal(uint256 proposalId) external {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        
        Proposal storage proposal = proposals[proposalId];
        
        // Validate voting has ended
        require(block.number > proposal.endBlock, "Voting still ongoing");
        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");
        
        // Count total votes
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        require(totalVotes > 0, "No votes cast");
        
        // Determine result: winner is whoever has more votes
        if (proposal.votesFor > proposal.votesAgainst) {
            proposal.state = ProposalState.SUCCEEDED;
        } else {
            proposal.state = ProposalState.DEFEATED;
        }
        
        emit ProposalFinalized(proposalId, proposal.state, proposal.votesFor, proposal.votesAgainst);
    }
    
    // ============ EXECUTE PROPOSAL ============
    
    /// @notice Execute a proposal that won the vote
    /// @param proposalId ID of the proposal
    function executeProposal(uint256 proposalId) external {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        
        Proposal storage proposal = proposals[proposalId];
        
        // Validate proposal
        require(proposal.state == ProposalState.SUCCEEDED, "Proposal did not succeed");
        require(!proposal.executed, "Already executed");
        
        // Mark as executed BEFORE calling (reentrancy protection)
        proposal.executed = true;
        proposal.state = ProposalState.EXECUTED;
        
        // Execute action based on type
        if (proposal.actionType == ActionType.SET_APY) {
            IVoteStake(voteStakeAddress).setAPY(proposal.actionValue);
        }
        // Additional action types can be added here
        
        emit ProposalExecuted(proposalId, proposal.actionType, proposal.actionValue);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /// @notice Get the current state of a proposal
    function getProposalState(uint256 proposalId) external view returns (ProposalState) {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        
        Proposal storage proposal = proposals[proposalId];
        
        if (proposal.executed) {
            return ProposalState.EXECUTED;
        }
        if (block.number <= proposal.endBlock) {
            return ProposalState.ACTIVE;
        }
        if (proposal.votesFor > proposal.votesAgainst) {
            return ProposalState.SUCCEEDED;
        }
        return ProposalState.DEFEATED;
    }
    
    /// @notice Get complete details of a proposal
    function getProposal(uint256 proposalId) external view returns (
        uint256 id,
        address proposer,
        string memory description,
        ActionType actionType,
        uint256 actionValue,
        uint256 startBlock,
        uint256 endBlock,
        uint256 votesFor,
        uint256 votesAgainst,
        ProposalState state,
        bool executed
    ) {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        
        Proposal storage p = proposals[proposalId];
        return (
            p.id,
            p.proposer,
            p.description,
            p.actionType,
            p.actionValue,
            p.startBlock,
            p.endBlock,
            p.votesFor,
            p.votesAgainst,
            p.state,
            p.executed
        );
    }
    
    /// @notice Get voting data for a proposal
    function getVoteData(uint256 proposalId) external view returns (
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 totalVotes
    ) {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        
        Proposal storage p = proposals[proposalId];
        uint256 total = p.votesFor + p.votesAgainst;
        return (p.votesFor, p.votesAgainst, total);
    }
    
    /// @notice Check if a user has already voted on a proposal
    function hasUserVoted(uint256 proposalId, address user) external view returns (bool) {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        return proposals[proposalId].hasVoted[user];
    }
    
    /// @notice Get the total number of proposals
    function getProposalCount() external view returns (uint256) {
        return proposalCounter;
    }
    
    /// @notice Get all proposal IDs
    function getProposalIds() external view returns (uint256[] memory) {
        return proposalIds;
    }
    
    /// @notice Get the vote choice of a user on a proposal
    function getUserVoteChoice(uint256 proposalId, address user) external view returns (bool) {
        require(proposalId < proposalCounter, "Invalid proposal ID");
        return proposals[proposalId].voteChoice[user];
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    /// @notice Change the voting period (owner only)
    function setVotingPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Period must be > 0");
        votingPeriod = newPeriod;
        emit VotingPeriodChanged(newPeriod);
    }
    
    /// @notice Change the minimum tokens required to create a proposal (owner only)
    function setMinProposalVotes(uint256 newMin) external onlyOwner {
        minProposalVotes = newMin;
        emit MinProposalVotesChanged(newMin);
    }
    
    /// @notice Change the required quorum (owner only)
    function setQuorumPercent(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 10000, "Invalid quorum");
        quorumPercent = newQuorum;
        emit QuorumPercentChanged(newQuorum);
    }
    
    /// @notice Change the VotingToken contract address (owner only)
    function setVotingTokenAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Invalid address");
        votingTokenAddress = newAddress;
    }
    
    /// @notice Change the VoteStake contract address (owner only)
    function setVoteStakeAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Invalid address");
        voteStakeAddress = newAddress;
    }
}