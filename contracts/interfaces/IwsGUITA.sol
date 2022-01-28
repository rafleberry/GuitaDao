// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

import "./IERC20.sol";

// Old wsGUITA interface
interface IwsGUITA is IERC20 {
    function wrap(uint256 _amount) external returns (uint256);

    function unwrap(uint256 _amount) external returns (uint256);

    function wGUITATosGUITA(uint256 _amount) external view returns (uint256);

    function sGUITATowGUITA(uint256 _amount) external view returns (uint256);
}
