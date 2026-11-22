// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEscrowVault} from "../../src/interfaces/IEscrowVault.sol";

/// @notice Nhận ETH từ `withdraw` rồi thử gọi lại vault trong `receive()`.
/// @dev Ghi lại selector lỗi của lần gọi lại để test kiểm tra bị chặn bởi `nonReentrant`.
contract ReentrancyAttacker {
    enum Attack {
        None,
        Withdraw,
        Release,
        Refund,
        ClaimTimeoutRefund,
        CreateEscrow,
        WithdrawTo
    }

    IEscrowVault public immutable vault;
    Attack public attack;
    uint256 public targetId;
    bool public reentered;
    bytes public reentryError;

    constructor(IEscrowVault vault_) {
        vault = vault_;
    }

    function setAttack(Attack attack_, uint256 targetId_) external {
        attack = attack_;
        targetId = targetId_;
    }

    function createEscrowEth(address seller, uint256 amount, address arbiter) external payable returns (uint256) {
        return vault.createEscrow{value: amount}(seller, address(0), amount, 1 days, arbiter, 500);
    }

    function markDelivered(uint256 id) external {
        vault.markDelivered(id);
    }

    function release(uint256 id) external {
        vault.release(id);
    }

    function raiseDispute(uint256 id) external {
        vault.raiseDispute(id);
    }

    function withdrawEth() external {
        vault.withdraw(address(0));
    }

    receive() external payable {
        if (attack == Attack.None || reentered) return;
        reentered = true;

        bytes memory data;
        uint256 value;
        if (attack == Attack.Withdraw) {
            data = abi.encodeCall(IEscrowVault.withdraw, (address(0)));
        } else if (attack == Attack.WithdrawTo) {
            data = abi.encodeCall(IEscrowVault.withdrawTo, (address(0), address(this)));
        } else if (attack == Attack.Release) {
            data = abi.encodeCall(IEscrowVault.release, (targetId));
        } else if (attack == Attack.Refund) {
            data = abi.encodeCall(IEscrowVault.refund, (targetId));
        } else if (attack == Attack.ClaimTimeoutRefund) {
            data = abi.encodeCall(IEscrowVault.claimTimeoutRefund, (targetId));
        } else {
            value = msg.value;
            data = abi.encodeCall(
                IEscrowVault.createEscrow, (address(0xBEEF), address(0), value, 1 days, address(0), 500)
            );
        }

        (bool ok, bytes memory ret) = address(vault).call{value: value}(data);
        // Lần gọi lại phải thất bại; lưu lỗi để test so sánh. Không revert để withdraw gốc vẫn thành công.
        if (!ok) reentryError = ret;
        else reentryError = hex"00";
    }
}
