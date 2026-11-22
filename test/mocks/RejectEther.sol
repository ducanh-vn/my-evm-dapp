// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IEscrowVault} from "../../src/interfaces/IEscrowVault.sol";

/// @notice Contract từ chối nhận ETH, đóng vai Seller để test `EthTransferFailed`.
contract RejectEther {
    function markDelivered(IEscrowVault vault, uint256 id) external {
        vault.markDelivered(id);
    }

    function withdraw(IEscrowVault vault, address token) external {
        vault.withdraw(token);
    }

    function withdrawTo(IEscrowVault vault, address token, address to) external {
        vault.withdrawTo(token, to);
    }

    receive() external payable {
        revert("no ETH");
    }
}
