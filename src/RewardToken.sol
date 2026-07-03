// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract RewardToken is ERC20, Ownable {

    constructor() ERC20("Reward Token", "RWT") Ownable(msg.sender) {
        
    }

}