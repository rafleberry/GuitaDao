// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.5;

import "../interfaces/IERC20.sol";
import "../types/Ownable.sol";

contract GuitaFaucet is Ownable {
    IERC20 public guita;

    constructor(address _guita) {
        guita = IERC20(_guita);
    }

    function setGuita(address _guita) external onlyOwner {
        guita = IERC20(_guita);
    }

    function dispense() external {
        guita.transfer(msg.sender, 1e9);
    }
}
