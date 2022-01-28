// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.5;

import "../interfaces/IERC20.sol";
import "../interfaces/IOwnable.sol";
import "../types/Ownable.sol";
import "../libraries/SafeERC20.sol";

contract CrossChainMigrator is Ownable {
    using SafeERC20 for IERC20;

    IERC20 internal immutable wsGUITA; // v1 token
    IERC20 internal immutable gGUITA; // v2 token

    constructor(address _wsGUITA, address _gGUITA) {
        require(_wsGUITA != address(0), "Zero address: wsGUITA");
        wsGUITA = IERC20(_wsGUITA);
        require(_gGUITA != address(0), "Zero address: gGUITA");
        gGUITA = IERC20(_gGUITA);
    }

    // migrate wsGUITA to gGUITA - 1:1 like kind
    function migrate(uint256 amount) external {
        wsGUITA.safeTransferFrom(msg.sender, address(this), amount);
        gGUITA.safeTransfer(msg.sender, amount);
    }

    // withdraw wsGUITA so it can be bridged on ETH and returned as more gGUITA
    function replenish() external onlyOwner {
        wsGUITA.safeTransfer(msg.sender, wsGUITA.balanceOf(address(this)));
    }

    // withdraw migrated wsGUITA and unmigrated gGUITA
    function clear() external onlyOwner {
        wsGUITA.safeTransfer(msg.sender, wsGUITA.balanceOf(address(this)));
        gGUITA.safeTransfer(msg.sender, gGUITA.balanceOf(address(this)));
    }
}
