// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";

/// @notice Fuzz: tổng các khoản ghi có luôn bằng `amount`, không mất wei, phí không vượt trần.
contract EscrowVaultFuzzTest is BaseTest {
    function _sumCredits() internal view returns (uint256) {
        return vault.withdrawable(buyer, address(usdc)) + vault.withdrawable(seller, address(usdc))
            + vault.withdrawable(feeRecipient, address(usdc));
    }

    function _create(uint256 amount, uint16 fee, uint48 period) internal returns (uint256 id) {
        vm.prank(owner);
        vault.setFeeBps(fee);
        usdc.mint(buyer, amount);
        vm.prank(buyer);
        id = vault.createEscrow(seller, address(usdc), amount, period, arbiter, MAX_FEE);
    }

    function testFuzz_Resolve_ConservesAmount(uint256 amount, uint16 fee, uint16 buyerBps, uint48 period, uint48 wait)
        public
    {
        amount = bound(amount, 1, 1e30);
        fee = uint16(bound(fee, 0, 500));
        buyerBps = uint16(bound(buyerBps, 0, 10_000));
        period = uint48(bound(period, 1 days, 90 days));

        uint256 id = _create(amount, fee, period);
        _dispute(id, buyer);
        wait = uint48(bound(wait, 0, 14 days));
        vm.warp(block.timestamp + wait);

        vm.prank(arbiter);
        vault.resolveDispute(id, buyerBps);

        uint256 buyerAmt = vault.withdrawable(buyer, address(usdc));
        uint256 feeAmt = vault.withdrawable(feeRecipient, address(usdc));
        assertEq(_sumCredits(), amount, "no wei lost");
        assertEq(buyerAmt, amount * buyerBps / 10_000);
        assertLe(feeAmt, (amount - buyerAmt) * 500 / 10_000, "fee <= cap");
        if (buyerBps == 10_000) assertEq(feeAmt, 0, "full buyer = no fee");
    }

    function testFuzz_Release_ConservesAmount(uint256 amount, uint16 fee, uint48 period, bool sellerPath) public {
        amount = bound(amount, 1, 1e30);
        fee = uint16(bound(fee, 0, 500));
        period = uint48(bound(period, 1 days, 90 days));

        uint256 id = _create(amount, fee, period);
        if (sellerPath) {
            _deliver(id);
            vm.warp(_windowEnd(id) + 1);
            vm.prank(seller);
        } else {
            vm.prank(buyer);
        }
        vault.release(id);

        assertEq(_sumCredits(), amount);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), amount * fee / 10_000);
    }

    function testFuzz_TimeoutRefund_FullAmountNoFee(uint256 amount, uint16 fee, uint48 extra) public {
        amount = bound(amount, 1, 1e30);
        fee = uint16(bound(fee, 0, 500));
        uint256 id = _create(amount, fee, PERIOD);
        _deliver(id);
        _dispute(id, seller);
        extra = uint48(bound(extra, 1, 3650 days));
        vm.warp(vault.getEscrow(id).arbitrationDeadline + extra);

        vm.prank(buyer);
        vault.claimTimeoutRefund(id);
        assertEq(vault.withdrawable(buyer, address(usdc)), amount);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), 0);
    }

    /// @dev Audit M-1: với mọi thời điểm giao hàng và mọi thời điểm gọi, đúng một trong hai hành động hợp lệ:
    ///      Buyer mở tranh chấp (now <= max(dispute, delivery)) hoặc Seller tự giải ngân (now > mốc đó).
    function testFuzz_DeliveredWindow_ExactlyOneOfDisputeOrSellerRelease(
        uint48 period,
        uint48 deliverAfter,
        uint48 callAfter
    ) public {
        period = uint48(bound(period, 1 days, 90 days));
        uint256 id = _create(AMOUNT, FEE_BPS, period);
        uint256 deliveryDeadline = vault.getEscrow(id).deliveryDeadline;

        deliverAfter = uint48(bound(deliverAfter, 0, period));
        vm.warp(vm.getBlockTimestamp() + deliverAfter);
        _deliver(id);

        uint256 end = _windowEnd(id);
        assertGe(end, deliveryDeadline);
        assertGe(end, vm.getBlockTimestamp() + 3 days);

        callAfter = uint48(bound(callAfter, 0, 120 days));
        uint256 target = vm.getBlockTimestamp() + callAfter;
        vm.warp(target);

        uint256 snap = vm.snapshotState();
        vm.prank(buyer);
        (bool disputeOk,) = address(vault).call(abi.encodeCall(vault.raiseDispute, (id)));
        vm.revertToState(snap);
        vm.prank(seller);
        (bool releaseOk,) = address(vault).call(abi.encodeCall(vault.release, (id)));

        assertTrue(disputeOk != releaseOk, "exactly one allowed");
        assertEq(disputeOk, target <= end);
    }

    function testFuzz_ArbitrationDeadlineBoundary(uint48 offset) public {
        uint256 id = _create(AMOUNT, FEE_BPS, PERIOD);
        _dispute(id, buyer);
        uint48 deadline = vault.getEscrow(id).arbitrationDeadline;
        offset = uint48(bound(offset, 0, 60 days));
        uint256 target = vm.getBlockTimestamp() + offset;
        vm.warp(target);

        if (target <= deadline) {
            vm.prank(buyer);
            vm.expectRevert(IEscrowVault.DeadlineNotReached.selector);
            vault.claimTimeoutRefund(id);
            vm.prank(arbiter);
            vault.resolveDispute(id, 0);
        } else {
            vm.prank(arbiter);
            vm.expectRevert(IEscrowVault.DeadlinePassed.selector);
            vault.resolveDispute(id, 0);
            vm.prank(buyer);
            vault.claimTimeoutRefund(id);
        }
    }
}
