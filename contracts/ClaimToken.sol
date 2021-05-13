pragma solidity 0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ClaimToken is ERC20("CLAIM", "CLAIM") {
    constructor() public {
        _setupDecimals(18);
        _mint(msg.sender,1e26);
    }
}

