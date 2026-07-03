# VoteStake

A staking protocol with dual rewards and on-chain governance built in Solidity. Users lock tokens for a chosen period, earn rewards based on a configurable APY, and receive — alongside the reward token — governance tokens that give them voting power over key protocol parameters, including the APY itself.

## What it does

VoteStake connects four contracts that work together:

- **StakingToken (STK)** — the ERC-20 token users deposit to stake.
- **RewardToken (RWT)** — the ERC-20 token minted as a reward on claim.
- **VotingToken (VOT)** — an ERC-20 with `ERC20Votes` extension (checkpoints + `permit`) minted alongside rewards, granting voting rights.
- **VoteStake** — the core staking contract: handles deposits, reward calculation, withdrawals (with or without penalty), and applies APY changes approved by governance.
- **Governance** — a simplified Compound/OZ Governor-style contract: proposal creation, voting with frozen (snapshot) voting power, finalization, and execution.

### Main flow

1. The user deposits `STK`, choosing a lock period (30, 60, or 90 days) → `deposit()`.
2. While the stake is locked, it accrues rewards based on the current APY.
3. Once the lock period ends, the user can claim (`claimRewards()`) or withdraw principal + rewards (`withdrawAfterLockup()`). Rewards are split 80% `RWT` / 20% `VOT`.
4. If the user needs to exit early, `withdrawEarly()` applies a penalty (10% by default) on the principal.
5. Holding `VOT`, any user with enough voting power can create proposals in `Governance` (e.g., changing the APY), and the community votes. If the proposal succeeds, it's executed and the change is automatically applied to `VoteStake`.

## Tech stack

- Solidity `^0.8.35`
- [Foundry](https://book.getfoundry.sh/) (Forge, Cast, Anvil)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/) — `Ownable`, `ERC20`, `ERC20Votes`, `ERC20Permit`

## Project structure

```
src/
├── VoteStake.sol           # Core staking contract
├── RewardToken.sol         # Reward ERC-20
├── VotingToken.sol         # Voting-power ERC-20 (ERC20Votes + Permit)
├── StakingToken.sol        # ERC-20 that gets staked
├── Governance.sol          # Proposal and voting contract
└── interfaces/
    └── IGovernance.sol     # IVotingToken / IVoteStake interfaces
```

## Contracts and key functions

### `VoteStake.sol`
| Function | Description |
|---|---|
| `deposit(amount, lockPeriodDays)` | Locks `amount` of `STK` for 30/60/90 days |
| `claimRewards()` | Claims rewards (80% RWT / 20% VOT) once the lock period is over |
| `withdrawAfterLockup()` | Withdraws principal + rewards after the lock period ends |
| `withdrawEarly()` | Withdraws early, subject to a penalty |
| `calculateReward(user)` | Calculates accrued rewards based on APY and elapsed time |
| `setAPY(newAPY)` | Can only be called by `Governance` after an approved proposal |
| `setGovernanceAddress(addr)` | Only the owner can update the governance address |

### `Governance.sol`
| Function | Description |
|---|---|
| `createProposal(description, actionType, actionValue)` | Creates a proposal (requires minimum voting power) |
| `castVote(proposalId, support)` | Votes for or against using voting power frozen at the snapshot |
| `finalizeProposal(proposalId)` | Closes voting and determines whether the proposal succeeded |
| `executeProposal(proposalId)` | Executes the action of an approved proposal (e.g. `setAPY`) |

## Installation

```bash
git clone https://github.com/sarad-blockchain/VoteStake.git
cd VoteStake
forge install
```

## Usage

### Build

```bash
forge build
```

### Tests

```bash
forge test
```

> The project doesn't include a test suite yet. It's the next planned step: Foundry coverage for deposits, reward calculation, early withdrawals, and the full governance cycle (create proposal → vote → finalize → execute).

### Local node (Anvil)

```bash
anvil
```

### Formatting

```bash
forge fmt
```

## Design notes

- Voting power is frozen via a snapshot at the block the proposal is created, preventing last-minute manipulation.
- `Governance` is the only address authorized (`onlyGovernance`) to change the APY on `VoteStake`, keeping staking logic separate from decision-making logic.
- The 80/20 reward split (reward / governance) incentivizes protocol participation while distributing voting power proportionally to those who stake.


## License

UNLICENSED