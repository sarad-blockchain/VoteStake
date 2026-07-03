// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Nonces.sol";

contract VotingToken is ERC20, ERC20Permit, ERC20Votes, Ownable {

    constructor() ERC20("Voting Token", "VOT") ERC20Permit("Voting Token") Ownable(msg.sender) {
        _mint(msg.sender, 1000 * 10 ** decimals()); // Mint 1000 tokens to the owner
    }

    // Owner can mint new governance tokens
    function mint (address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Override hooks required by ERC20Votes
    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}