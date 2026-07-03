// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Minimal interface for tokens that can be minted by this contract
interface IVoteStakeMintable {
    function mint(address to, uint256 amount) external;
}

contract VoteStake is Ownable {
    
    // State Variable
    address public stakingToken;
    address public rewardToken;
    address public votingToken;
    address public governanceAddress;
    uint256 public currentAPY = 1200; // 12%
    uint256 public penaltyRate = 1000; // 10% penalty for early withdrawal

    // How much Token A is staked by each user
    mapping(address => uint256) public userBalances;

    // How much deposit is stake for each user
    mapping(address => uint256) public depositTimestamp;

    // What lock period the user chose (30, 60, or 90)
    mapping(address => uint256) public lockPeriodDays;

    // user can only have one active lock at a time   
    mapping(address => bool) public hasActiveLock;

    // User can only vote once per governance proposal
    mapping(address => bool) public hasVotedOnRewards;

    // permit only valid lock periods (30, 60, 90)
    uint256[] public validLockPeriods = [30, 60, 90];

    // Event
    event RewardsClaimed(address indexed user, uint256 rewardTokenAmount, uint256 votingTokenAmount);
    event WithdrawalAfterLock(address indexed user, uint256 stakedAmount, uint256 rewardTokenAmount, uint256 votingTokenAmount);
    event Deposited(address indexed user, uint256 amount, uint256 lockDays);
    event EarlyWithdrawal(address indexed user, uint256 amount, uint256 penalty);
    event APYChanged(uint256 newAPY);
    event GovernanceAddressChanged(address newGovernance);


   // Modifiers
   modifier onlyGovernance() {
        require(msg.sender == governanceAddress, "Not authorized");
        _;
    }

   constructor (address _stakingToken, address _rewardToken, address _votingToken, address _governanceAddress) Ownable(msg.sender) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        votingToken = _votingToken;
        governanceAddress = _governanceAddress;
    }

    function setAPY(uint256 newAPY) external onlyGovernance {
        require(newAPY <= 10000, "APY too high"); // Max 100%
        currentAPY = newAPY;
        emit APYChanged(newAPY);
    }
            
    // function deposit
    function deposit(uint256 amount, uint256 lockPeriodDays_) external {
        require(isValidLockPeriod(lockPeriodDays_), "Invalid lock period");
        require(!hasActiveLock[msg.sender], "Active lock exists");

        userBalances[msg.sender] += amount;
        IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);

        depositTimestamp[msg.sender] = block.timestamp;
        lockPeriodDays[msg.sender] = lockPeriodDays_;
        hasActiveLock[msg.sender] = true;

        emit Deposited(msg.sender, amount, lockPeriodDays_);
    }

    // function claimRewards
    function claimRewards() external {
        require(hasActiveLock[msg.sender], "No active lock");
    
       // Validate that the lock period has passed
        uint256 lockPeriod = lockPeriodDays[msg.sender];
        require(block.timestamp >= depositTimestamp[msg.sender] + (lockPeriod * 1 days), "Lock period not completed");
    
        uint256 rewardAmount = calculateReward(msg.sender);
    
       // Distribute 80/20
       uint256 rewardTokenAmount = (rewardAmount * 80) / 100;
       uint256 votingTokenAmount = (rewardAmount * 20) / 100;
       
       // Mint reward and voting tokens to the user (requires mintable token implementations)
       IVoteStakeMintable(rewardToken).mint(msg.sender, rewardTokenAmount);
       IVoteStakeMintable(votingToken).mint(msg.sender, votingTokenAmount);
    
       // Clean up user state after claiming rewards
       userBalances[msg.sender] = 0;
       hasActiveLock[msg.sender] = false;
       depositTimestamp[msg.sender] = 0;
       lockPeriodDays[msg.sender] = 0;
    
       emit RewardsClaimed(msg.sender, rewardTokenAmount, votingTokenAmount);
    }
    
    
    // function withdrawEarly
    function withdrawEarly() external {
        require(hasActiveLock[msg.sender], "No active lock");
        uint256 originalStake = userBalances[msg.sender];
        uint256 penalty = (originalStake * penaltyRate) / 10000;
        uint256 amountToReturn = originalStake - penalty;

        userBalances[msg.sender] = 0; 
        IERC20(stakingToken).transfer(msg.sender, amountToReturn);

        depositTimestamp[msg.sender] = 0;
        lockPeriodDays[msg.sender] = 0;
        hasActiveLock[msg.sender] = false;
        emit EarlyWithdrawal(msg.sender, originalStake, penalty);
    }
 

    // function withdrawAfterLockup
    function withdrawAfterLockup() external {
        require(hasActiveLock[msg.sender], "No active lock");
        uint256 lockPeriod = lockPeriodDays[msg.sender];
        require(block.timestamp >= depositTimestamp[msg.sender] + (lockPeriod * 1 days), "Lock period not over");

        uint256 stakedAmount = userBalances[msg.sender];

         // Calculate and distribute rewards
         uint256 rewardAmount = calculateReward(msg.sender);
         uint256 rewardTokenAmount = (rewardAmount * 80) / 100;
         uint256 votingTokenAmount = (rewardAmount * 20) / 100;

        // Return staked tokens to the user
        userBalances[msg.sender] -= stakedAmount;
        IERC20(stakingToken).transfer(msg.sender, stakedAmount);
    
        // Distribute rewards
        IVoteStakeMintable(rewardToken).mint(msg.sender, rewardTokenAmount);
        IVoteStakeMintable(votingToken).mint(msg.sender, votingTokenAmount);

        depositTimestamp[msg.sender] = 0;
        lockPeriodDays[msg.sender] = 0;
        hasActiveLock[msg.sender] = false;

         
        emit WithdrawalAfterLock(msg.sender, stakedAmount, rewardTokenAmount, votingTokenAmount);
    }


// function admin setAPY AND setGovernanceAddress

     // fucntion view (only read) getUserInfo , getRewardAmount , isValidLockPeriod ,   getValidLockPeriods

     function getUserInfo(address user) external view returns (uint256 balance, uint256 lockPeriod, uint256 depositTime, bool activeLock) {
        return (userBalances[user], lockPeriodDays[user], depositTimestamp[user], hasActiveLock[user]);
    }

    function getRewardAmount(address user) external view returns (uint256) {
        return calculateReward(user);
    }

    function getValidLockPeriods() external view returns (uint256[] memory) {
        return validLockPeriods;
    }

    
    // function calculateReward
    function calculateReward(address user) public view returns (uint256) {
        uint256 stakedAmount = userBalances[user];
        uint256 timeElapsed = block.timestamp - depositTimestamp[user];
        uint256 reward = (stakedAmount * currentAPY * timeElapsed) / (10000 * 365 days); 
        return reward;
    }

    // function isValidLockPeriod
    function isValidLockPeriod(uint256 lockPeriod) internal view returns (bool) {
        for (uint256 i = 0; i < validLockPeriods.length; i++) {
            if (validLockPeriods[i] == lockPeriod) {
                return true;
            }
        }
        return false;
    }

    function setGovernanceAddress(address newGovernance) external onlyOwner {
        require(newGovernance != address(0), "Invalid address");
        governanceAddress = newGovernance;
        emit GovernanceAddressChanged(newGovernance);
    }
}


