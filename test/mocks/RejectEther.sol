// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEscrowVault} from "../../src/interfaces/IEscrowVault.sol";

/// @notice Contract từ chối nhận ETH, đóng vai Seller để test `EthTransferFailed`.
contract RejectEther {
    function markDelivered(IEscrowVault vault, uint256 id) external {
        vault.markDelivered(id);
    }

    function withdraw(IEscrowVault vault, address token) external {
        vault.withdraw(token);
    }

    receive() external payable {
        revert("no ETH");
    }
}
