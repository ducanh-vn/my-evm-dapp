// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";

contract EscrowVaultRefundTest is BaseTest {
    function _assertFullRefund(uint256 id) internal view {
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Refunded));
        assertEq(vault.withdrawable(buyer, address(usdc)), AMOUNT);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), 0, "no fee");
        assertEq(vault.withdrawable(seller, address(usdc)), 0);
    }

    function test_SellerRefund_WhenFunded() public {
        uint256 id = _createUsdc();
        vm.expectEmit(address(vault));
        emit IEscrowVault.EscrowRefunded(id, seller, AMOUNT);
        vm.prank(seller);
        vault.refund(id);
        _assertFullRefund(id);
    }

    function test_SellerRefund_WhenDelivered() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.prank(seller);
        vault.refund(id);
        _assertFullRefund(id);
    }

    function test_SellerRefund_WhenDisputed() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.prank(seller);
        vault.refund(id);
        _assertFullRefund(id);
    }

    function test_BuyerRefund_AfterDeliveryDeadline() public {
        uint256 id = _createUsdc();
        vm.warp(vault.getEscrow(id).deliveryDeadline + 1);
        vm.prank(buyer);
        vault.refund(id);
        _assertFullRefund(id);

        vm.prank(buyer);
        vault.withdraw(address(usdc));
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_RevertWhen_BuyerRefundBeforeDeadline() public {
        uint256 id = _createUsdc();
        vm.warp(vault.getEscrow(id).deliveryDeadline);
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.DeadlineNotReached.selector);
        vault.refund(id);
    }

    function test_RevertWhen_BuyerRefundWhenDelivered() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.warp(vault.getEscrow(id).deliveryDeadline + 1);
        vm.prank(buyer);
        _expectInvalidStatus(id, IEscrowVault.Status.Delivered);
        vault.refund(id);
    }

    /*//////////////////////////////////////////////////////////////
             BUYER CHỈ REFUND KHI FUNDED VÀ QUÁ deliveryDeadline
    //////////////////////////////////////////////////////////////*/

    /// @dev Khi đã Delivered, Buyer không bao giờ refund được, ở bất kỳ thời điểm nào.
    function testFuzz_RevertWhen_BuyerRefundOnceDelivered(uint48 deliverAfter, uint48 wait) public {
        uint256 id = _createUsdc();
        deliverAfter = uint48(bound(deliverAfter, 0, PERIOD));
        vm.warp(vm.getBlockTimestamp() + deliverAfter);
        _deliver(id);
        wait = uint48(bound(wait, 0, 365 days));
        vm.warp(vm.getBlockTimestamp() + wait);

        vm.prank(buyer);
        _expectInvalidStatus(id, IEscrowVault.Status.Delivered);
        vault.refund(id);
    }

    function test_RevertWhen_BuyerRefundDelivered_AtEachDeadline() public {
        uint256 id = _createUsdc();
        _deliver(id);
        IEscrowVault.Escrow memory e = vault.getEscrow(id);
        uint256[5] memory times = [
            uint256(e.disputeDeadline),
            uint256(e.disputeDeadline) + 1,
            uint256(e.deliveryDeadline),
            uint256(e.deliveryDeadline) + 1,
            _windowEnd(id) + 30 days
        ];
        for (uint256 i; i < times.length; ++i) {
            vm.warp(times[i]);
            vm.prank(buyer);
            _expectInvalidStatus(id, IEscrowVault.Status.Delivered);
            vault.refund(id);
        }
        // Buyer vẫn còn release hoặc (trong hạn) raiseDispute.
        vm.prank(buyer);
        vault.release(id);
    }

    function test_RevertWhen_BuyerRefundWhenDisputed() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.warp(vault.getEscrow(id).deliveryDeadline + 1);
        vm.prank(buyer);
        _expectInvalidStatus(id, IEscrowVault.Status.Disputed);
        vault.refund(id);
    }

    function test_BuyerRefund_ExactDeliveryDeadlineBoundary() public {
        uint256 id = _createUsdc();
        uint48 deadline = vault.getEscrow(id).deliveryDeadline;
        vm.warp(deadline);
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.DeadlineNotReached.selector);
        vault.refund(id);

        vm.warp(uint256(deadline) + 1);
        vm.prank(buyer);
        vault.refund(id);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Refunded));
    }

    function test_SellerVoluntaryRefund_DeliveredAfterWindow() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.warp(_windowEnd(id) + 1);
        vm.prank(seller);
        vault.refund(id);
        assertEq(vault.withdrawable(buyer, address(usdc)), AMOUNT);
    }

    function test_RevertWhen_StrangerRefund() public {
        uint256 id = _createUsdc();
        vm.prank(stranger);
        vm.expectRevert(IEscrowVault.Unauthorized.selector);
        vault.refund(id);
    }

    function test_RevertWhen_RefundAfterRelease() public {
        uint256 id = _createUsdc();
        vm.prank(buyer);
        vault.release(id);
        vm.prank(seller);
        _expectInvalidStatus(id, IEscrowVault.Status.Released);
        vault.refund(id);
    }

    function test_RevertWhen_DoubleRefund() public {
        uint256 id = _createUsdc();
        vm.startPrank(seller);
        vault.refund(id);
        _expectInvalidStatus(id, IEscrowVault.Status.Refunded);
        vault.refund(id);
        vm.stopPrank();
    }

    function test_RevertWhen_EscrowNotFound() public {
        vm.startPrank(buyer);
        bytes memory err = abi.encodeWithSelector(IEscrowVault.EscrowNotFound.selector, 42);
        vm.expectRevert(err);
        vault.refund(42);
        vm.expectRevert(err);
        vault.release(42);
        vm.expectRevert(err);
        vault.raiseDispute(42);
        vm.expectRevert(err);
        vault.claimTimeoutRefund(42);
        vm.expectRevert(err);
        vault.markDelivered(42);
        vm.expectRevert(err);
        vault.resolveDispute(42, 0);
        vm.stopPrank();
    }
}
