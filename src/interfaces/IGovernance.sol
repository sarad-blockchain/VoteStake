// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

/// @title IVotingToken
/// @notice Interface for the VotingToken contract
/// @dev Used to interact with voting token functionality
interface IVotingToken {
    /// @notice Get the past voting power of an account at a specific block
    /// @param account The address to check
    /// @param blockNumber The block number to query
    /// @return The voting power at the specified block
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /// @notice Create a snapshot of the current voting state
    /// @return The snapshot ID
    function snapshot() external returns (uint256);
}

/// @title IVoteStake
/// @notice Interface for the VoteStake contract
/// @dev Used to interact with staking and APY management
interface IVoteStake {
    /// @notice Set a new Annual Percentage Yield (APY)
    /// @param newAPY The new APY value to set
    function setAPY(uint256 newAPY) external;
}
