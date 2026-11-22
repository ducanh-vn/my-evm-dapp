// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RejectEther} from "./mocks/RejectEther.sol";
import {ReentrancyAttacker} from "./mocks/ReentrancyAttacker.sol";
import {BlacklistERC20} from "./mocks/BlacklistERC20.sol";

contract EscrowVaultWithdrawTest is BaseTest {
    function test_Withdraw_EmitsAndZeroesBalance() public {
        uint256 id = _createUsdc();
        vm.prank(seller);
        vault.refund(id);

        vm.expectEmit(address(vault));
        emit IEscrowVault.Withdrawn(buyer, address(usdc), buyer, AMOUNT);
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
        uint256 id = vault.createEscrow{value: ETH_AMOUNT}(address(rejecter), ETH, ETH_AMOUNT, PERIOD, arbiter, MAX_FEE);
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
                         AUDIT L-3: withdrawTo
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawTo_Usdc_SendsToRecipient() public {
        uint256 id = _createUsdc();
        vm.prank(buyer);
        vault.release(id);
        uint256 owed = AMOUNT - _fee(AMOUNT);
        address cold = makeAddr("cold");

        vm.expectEmit(address(vault));
        emit IEscrowVault.Withdrawn(seller, address(usdc), cold, owed);
        vm.prank(seller);
        vault.withdrawTo(address(usdc), cold);

        assertEq(usdc.balanceOf(cold), owed);
        assertEq(usdc.balanceOf(seller), 0);
        assertEq(vault.withdrawable(seller, address(usdc)), 0);

        vm.prank(seller);
        vm.expectRevert(IEscrowVault.NothingToWithdraw.selector);
        vault.withdrawTo(address(usdc), cold);
    }

    function test_WithdrawTo_Eth_SendsToRecipient() public {
        uint256 id = _createEth();
        vm.prank(seller);
        vault.refund(id);
        address cold = makeAddr("cold");
        uint256 before = buyer.balance;

        vm.prank(buyer);
        vault.withdrawTo(ETH, cold);
        assertEq(cold.balance, ETH_AMOUNT);
        assertEq(buyer.balance, before);
    }

    function test_RevertWhen_WithdrawToZeroAddress() public {
        uint256 id = _createUsdc();
        vm.prank(seller);
        vault.refund(id);
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        vault.withdrawTo(address(usdc), address(0));
        assertEq(vault.withdrawable(buyer, address(usdc)), AMOUNT);
    }

    function test_RevertWhen_WithdrawToNothing() public {
        vm.prank(stranger);
        vm.expectRevert(IEscrowVault.NothingToWithdraw.selector);
        vault.withdrawTo(ETH, stranger);
    }

    function test_RevertWhen_WithdrawToRecipientRejectsEth_BalanceKept() public {
        RejectEther rejecter = new RejectEther();
        uint256 id = _createEth();
        vm.prank(seller);
        vault.refund(id);

        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.EthTransferFailed.selector);
        vault.withdrawTo(ETH, address(rejecter));
        assertEq(vault.withdrawable(buyer, ETH), ETH_AMOUNT, "balance kept");
    }

    /// @dev Seller là contract không nhận ETH: `withdraw` luôn lỗi, `withdrawTo` cứu được tiền.
    function test_WithdrawTo_RescuesSellerThatRejectsEth() public {
        RejectEther rejecter = new RejectEther();
        vm.prank(buyer);
        uint256 id = vault.createEscrow{value: ETH_AMOUNT}(address(rejecter), ETH, ETH_AMOUNT, PERIOD, arbiter, MAX_FEE);
        vm.prank(buyer);
        vault.release(id);
        uint256 owed = ETH_AMOUNT - _fee(ETH_AMOUNT);

        vm.expectRevert(IEscrowVault.EthTransferFailed.selector);
        rejecter.withdraw(vault, ETH);

        address rescue = makeAddr("rescue");
        rejecter.withdrawTo(vault, ETH, rescue);
        assertEq(rescue.balance, owed);
        assertEq(vault.withdrawable(address(rejecter), ETH), 0);
    }

    /// @dev Seller bị nhà phát hành token blacklist: `withdraw` lỗi, `withdrawTo` sang ví khác thành công.
    function test_WithdrawTo_RescuesBlacklistedSeller() public {
        BlacklistERC20 bl = new BlacklistERC20();
        vm.prank(owner);
        vault.setTokenAllowed(address(bl), true);
        bl.mint(buyer, AMOUNT);
        vm.startPrank(buyer);
        bl.approve(address(vault), AMOUNT);
        uint256 id = vault.createEscrow(seller, address(bl), AMOUNT, PERIOD, arbiter, MAX_FEE);
        vault.release(id);
        vm.stopPrank();
        bl.setBlacklisted(seller, true);
        uint256 owed = AMOUNT - _fee(AMOUNT);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(BlacklistERC20.Blacklisted.selector, seller));
        vault.withdraw(address(bl));
        assertEq(vault.withdrawable(seller, address(bl)), owed, "balance kept");

        address fresh = makeAddr("fresh");
        vm.prank(seller);
        vault.withdrawTo(address(bl), fresh);
        assertEq(bl.balanceOf(fresh), owed);

        // Ví nhận phí không bị ảnh hưởng.
        vm.prank(feeRecipient);
        vault.withdraw(address(bl));
        assertEq(bl.balanceOf(feeRecipient), _fee(AMOUNT));
    }

    function test_WithdrawTo_WorksWhilePaused() public {
        uint256 id = _createUsdc();
        vm.prank(seller);
        vault.refund(id);
        vm.prank(owner);
        vault.pause();
        vm.prank(buyer);
        vault.withdrawTo(address(usdc), makeAddr("cold"));
        assertEq(vault.withdrawable(buyer, address(usdc)), 0);
    }

    /// @dev Không ai rút được số dư của người khác: withdrawTo chỉ trừ số dư của msg.sender.
    function test_WithdrawTo_CannotDrainOthers() public {
        uint256 id = _createUsdc();
        vm.prank(seller);
        vault.refund(id);
        vm.prank(stranger);
        vm.expectRevert(IEscrowVault.NothingToWithdraw.selector);
        vault.withdrawTo(address(usdc), stranger);
        assertEq(vault.withdrawable(buyer, address(usdc)), AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                               REENTRANCY
    //////////////////////////////////////////////////////////////*/

    /// @dev Attacker là Seller của escrow `paidId` (đã release) và Buyer của escrow `targetId`.
    function _setupAttacker() internal returns (ReentrancyAttacker attacker, uint256 targetId) {
        attacker = new ReentrancyAttacker(vault);
        vm.deal(address(attacker), 10 ether);

        vm.prank(buyer);
        uint256 paidId =
            vault.createEscrow{value: ETH_AMOUNT}(address(attacker), ETH, ETH_AMOUNT, PERIOD, arbiter, MAX_FEE);
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

    function test_Reentrancy_WithdrawTo() public {
        _runAttack(ReentrancyAttacker.Attack.WithdrawTo);
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
