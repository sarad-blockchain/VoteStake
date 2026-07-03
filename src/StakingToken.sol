// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";


contract StakingToken is ERC20, Ownable {

    constructor() ERC20("Staking Token", "STK") Ownable(msg.sender) {
        _mint(msg.sender, 1000 * 10 ** decimals()); // Mint 1000 tokens to the owner
    }

    function mint (address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

}