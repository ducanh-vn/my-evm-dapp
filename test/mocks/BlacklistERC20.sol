// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "./MockERC20.sol";

/// @notice Mô phỏng cơ chế blacklist của USDC/USDT: địa chỉ bị chặn không gửi/nhận được token.
contract BlacklistERC20 is MockERC20 {
    error Blacklisted(address account);

    mapping(address => bool) public isBlacklisted;

    function setBlacklisted(address account, bool value) external {
        isBlacklisted[account] = value;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (isBlacklisted[from]) revert Blacklisted(from);
        if (isBlacklisted[to]) revert Blacklisted(to);
        super._update(from, to, value);
    }
}
