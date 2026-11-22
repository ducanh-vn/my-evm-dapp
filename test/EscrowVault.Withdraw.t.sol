// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RejectEther} from "./mocks/RejectEther.sol";
import {ReentrancyAttacker} from "./mocks/ReentrancyAttacker.sol";

contract EscrowVaultWithdrawTest is BaseTest {
    function test_Withdraw_EmitsAndZeroesBalance() public {
        uint256 id = _createUsdc();
        vm.prank(seller);
        vault.refund(id);

        vm.expectEmit(address(vault));
        emit IEscrowVault.Withdrawn(buyer, address(usdc), AMOUNT);
        vm.prank(buyer);
        vault.withdraw(address(usdc));
        assertEq(vault.withdrawable(buyer, address(usdc)), 0);
    }

    function test_RevertWhen_NothingToWithdraw() public {
        vm.prank(stranger);
        vm.expectRevert(IEscrowVault.NothingToWithdraw.selector);
        vault.withdraw(ETH);
    }

    function test_RevertWhen_EthRecipientRejects_BalanceKept() public {
        RejectEther rejecter = new RejectEther();
        vm.prank(buyer);
        uint256 id = vault.createEscrow{value: ETH_AMOUNT}(address(rejecter), ETH, ETH_AMOUNT, PERIOD, arbiter);
        vm.prank(buyer);
        vault.release(id);

        uint256 expected = ETH_AMOUNT - _fee(ETH_AMOUNT);
        vm.expectRevert(IEscrowVault.EthTransferFailed.selector);
        rejecter.withdraw(vault, ETH);
        assertEq(vault.withdrawable(address(rejecter), ETH), expected, "balance kept");

        // Ví nhận phí không bị ảnh hưởng bởi Seller lỗi.
        vm.prank(feeRecipient);
        vault.withdraw(ETH);
        assertEq(feeRecipient.balance, _fee(ETH_AMOUNT));
    }

    /*//////////////////////////////////////////////////////////////
                               REENTRANCY
    //////////////////////////////////////////////////////////////*/

    /// @dev Attacker là Seller của escrow `paidId` (đã release) và Buyer của escrow `targetId`.
    function _setupAttacker() internal returns (ReentrancyAttacker attacker, uint256 targetId) {
        attacker = new ReentrancyAttacker(vault);
        vm.deal(address(attacker), 10 ether);

        vm.prank(buyer);
        uint256 paidId = vault.createEscrow{value: ETH_AMOUNT}(address(attacker), ETH, ETH_AMOUNT, PERIOD, arbiter);
        vm.prank(buyer);
        vault.release(paidId);

        targetId = attacker.createEscrowEth(seller, ETH_AMOUNT, arbiter);
    }

    function _assertBlocked(ReentrancyAttacker attacker) internal view {
        assertTrue(attacker.reentered(), "receive ran");
        assertEq(attacker.reentryError(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
    }

    function _runAttack(ReentrancyAttacker.Attack kind) internal returns (ReentrancyAttacker attacker, uint256 tid) {
        (attacker, tid) = _setupAttacker();
        attacker.setAttack(kind, tid);
        uint256 credited = vault.withdrawable(address(attacker), ETH);
        uint256 before = address(attacker).balance;

        attacker.withdrawEth();

        _assertBlocked(attacker);
        assertEq(address(attacker).balance, before + credited, "paid exactly once");
        assertEq(vault.withdrawable(address(attacker), ETH), 0);
    }

    function test_Reentrancy_Withdraw() public {
        _runAttack(ReentrancyAttacker.Attack.Withdraw);
    }

    function test_Reentrancy_Release() public {
        (, uint256 tid) = _runAttack(ReentrancyAttacker.Attack.Release);
        assertEq(uint8(_status(tid)), uint8(IEscrowVault.Status.Funded));
    }

    function test_Reentrancy_Refund() public {
        (, uint256 tid) = _runAttack(ReentrancyAttacker.Attack.Refund);
        assertEq(uint8(_status(tid)), uint8(IEscrowVault.Status.Funded));
    }

    function test_Reentrancy_ClaimTimeoutRefund() public {
        (ReentrancyAttacker attacker, uint256 tid) = _setupAttacker();
        attacker.raiseDispute(tid);
        vm.warp(vault.getEscrow(tid).arbitrationDeadline + 1);
        attacker.setAttack(ReentrancyAttacker.Attack.ClaimTimeoutRefund, tid);

        attacker.withdrawEth();

        _assertBlocked(attacker);
        assertEq(uint8(_status(tid)), uint8(IEscrowVault.Status.Disputed));
    }

    function test_Reentrancy_CreateEscrow() public {
        uint256 countBefore;
        (ReentrancyAttacker attacker,) = _setupAttacker();
        countBefore = vault.nextEscrowId();
        attacker.setAttack(ReentrancyAttacker.Attack.CreateEscrow, 0);

        attacker.withdrawEth();

        _assertBlocked(attacker);
        assertEq(vault.nextEscrowId(), countBefore);
    }
}
