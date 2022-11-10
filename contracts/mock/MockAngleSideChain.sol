// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "../bridgeERC20/TokenSideChainMultiBridge.sol";

/// @title MockAngleSideChain
/// @author Angle Core Team
contract MockAngleSideChain is TokenSideChainMultiBridge {
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
