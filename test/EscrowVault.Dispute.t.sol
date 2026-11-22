// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";

contract EscrowVaultDisputeTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                             RAISE DISPUTE
    //////////////////////////////////////////////////////////////*/

    function test_RaiseDispute_ByBuyerWhenFunded() public {
        uint256 id = _createUsdc();
        uint48 expected = uint48(block.timestamp) + 14 days;
        vm.expectEmit(address(vault));
        emit IEscrowVault.DisputeRaised(id, buyer, expected);
        _dispute(id, buyer);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Disputed));
        assertEq(vault.getEscrow(id).arbitrationDeadline, expected);
    }

    function test_RaiseDispute_BySellerWhenDelivered() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.warp(vault.getEscrow(id).disputeDeadline);
        _dispute(id, seller);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Disputed));
    }

    function test_RevertWhen_RaiseDisputeByStranger() public {
        uint256 id = _createUsdc();
        vm.prank(stranger);
        vm.expectRevert(IEscrowVault.Unauthorized.selector);
        vault.raiseDispute(id);
    }

    function test_RevertWhen_RaiseDisputeAfterDeliveryDeadline() public {
        uint256 id = _createUsdc();
        vm.warp(vault.getEscrow(id).deliveryDeadline + 1);
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.DeadlinePassed.selector);
        vault.raiseDispute(id);
    }

    function test_RevertWhen_RaiseDisputeAfterDisputeWindow() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.warp(_windowEnd(id) + 1);
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.DeadlinePassed.selector);
        vault.raiseDispute(id);
    }

    /// @dev Audit M-1: qua disputeDeadline nhưng chưa qua deliveryDeadline thì Buyer vẫn khiếu nại được.
    function test_RaiseDispute_DeliveredAfterDisputeDeadlineBeforeDeliveryDeadline() public {
        uint256 id = _createUsdc();
        _deliver(id);
        IEscrowVault.Escrow memory e = vault.getEscrow(id);
        vm.warp(uint256(e.disputeDeadline) + 1);
        _dispute(id, buyer);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Disputed));
    }

    /// @dev Biên chính xác: tại mốc chỉ khiếu nại được; tại mốc + 1 chỉ Seller tự giải ngân được.
    function test_DeliveredWindowBoundary_NoGapNoOverlap() public {
        uint256 a = _createUsdc();
        uint256 b = _createUsdc();
        _deliver(a);
        _deliver(b);
        uint256 end = _windowEnd(a);
        assertEq(end, _windowEnd(b));

        vm.warp(end);
        vm.prank(seller);
        vm.expectRevert(IEscrowVault.DeadlineNotReached.selector);
        vault.release(a);
        _dispute(a, buyer); // vẫn hợp lệ tại đúng mốc

        vm.warp(end + 1);
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.DeadlinePassed.selector);
        vault.raiseDispute(b);
        vm.prank(seller);
        vault.release(b); // hợp lệ ngay sau mốc
    }

    function test_RevertWhen_RaiseDisputeTwice() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.prank(seller);
        _expectInvalidStatus(id, IEscrowVault.Status.Disputed);
        vault.raiseDispute(id);
    }

    /*//////////////////////////////////////////////////////////////
                            RESOLVE DISPUTE
    //////////////////////////////////////////////////////////////*/

    function test_Resolve_FullBuyer_NoFee() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.expectEmit(address(vault));
        emit IEscrowVault.DisputeResolved(id, arbiter, 10_000, AMOUNT, 0, 0);
        vm.prank(arbiter);
        vault.resolveDispute(id, 10_000);

        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Resolved));
        assertEq(vault.withdrawable(buyer, address(usdc)), AMOUNT);
        assertEq(vault.withdrawable(seller, address(usdc)), 0);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), 0);
    }

    function test_Resolve_FullSeller_FeeLikeRelease() public {
        uint256 id = _createUsdc();
        _dispute(id, seller);
        vm.prank(arbiter);
        vault.resolveDispute(id, 0);

        uint256 fee = _fee(AMOUNT);
        assertEq(vault.withdrawable(buyer, address(usdc)), 0);
        assertEq(vault.withdrawable(seller, address(usdc)), AMOUNT - fee);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), fee);
    }

    function test_Resolve_60_40_FeeOnlyOnSellerShare() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.prank(arbiter);
        vault.resolveDispute(id, 6_000);

        uint256 buyerAmt = AMOUNT * 6_000 / 10_000;
        uint256 sellerGross = AMOUNT - buyerAmt;
        uint256 fee = _fee(sellerGross);
        assertEq(vault.withdrawable(buyer, address(usdc)), buyerAmt);
        assertEq(vault.withdrawable(seller, address(usdc)), sellerGross - fee);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), fee);
    }

    function test_Resolve_AtExactDeadline() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        uint48 deadline = vault.getEscrow(id).arbitrationDeadline;
        vm.warp(deadline);

        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.DeadlineNotReached.selector);
        vault.claimTimeoutRefund(id);

        vm.prank(arbiter);
        vault.resolveDispute(id, 5_000);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Resolved));
    }

    function test_RevertWhen_ResolveByNonArbiter() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        address[4] memory callers = [owner, defaultArbiter, buyer, stranger];
        for (uint256 i; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(IEscrowVault.Unauthorized.selector);
            vault.resolveDispute(id, 5_000);
        }
    }

    function test_RevertWhen_ResolveBpsTooHigh() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidBps.selector, 10_001));
        vault.resolveDispute(id, 10_001);
    }

    function test_RevertWhen_ResolveNotDisputed() public {
        uint256 id = _createUsdc();
        vm.prank(arbiter);
        _expectInvalidStatus(id, IEscrowVault.Status.Funded);
        vault.resolveDispute(id, 5_000);
    }

    function test_RevertWhen_ResolveTwice() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.startPrank(arbiter);
        vault.resolveDispute(id, 5_000);
        _expectInvalidStatus(id, IEscrowVault.Status.Resolved);
        vault.resolveDispute(id, 5_000);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    ARBITRATION TIMEOUT (14 NGÀY)
    //////////////////////////////////////////////////////////////*/

    function test_ClaimTimeoutRefund_AfterDeadline() public {
        uint256 id = _createUsdc();
        _deliver(id);
        _dispute(id, seller);
        vm.warp(vault.getEscrow(id).arbitrationDeadline + 1);

        vm.expectEmit(address(vault));
        emit IEscrowVault.EscrowRefunded(id, buyer, AMOUNT);
        vm.prank(buyer);
        vault.claimTimeoutRefund(id);

        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Refunded));
        assertEq(vault.withdrawable(buyer, address(usdc)), AMOUNT);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), 0, "no fee");

        vm.prank(buyer);
        vault.withdraw(address(usdc));
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_RevertWhen_ResolveAfterTimeout() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.warp(vault.getEscrow(id).arbitrationDeadline + 1);
        vm.prank(arbiter);
        vm.expectRevert(IEscrowVault.DeadlinePassed.selector);
        vault.resolveDispute(id, 0);
    }

    function test_RevertWhen_ClaimTimeoutByNonBuyer() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.warp(vault.getEscrow(id).arbitrationDeadline + 1);
        address[3] memory callers = [seller, arbiter, owner];
        for (uint256 i; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(IEscrowVault.Unauthorized.selector);
            vault.claimTimeoutRefund(id);
        }
    }

    function test_RevertWhen_ClaimTimeoutNotDisputed() public {
        uint256 id = _createUsdc();
        vm.warp(block.timestamp + 30 days);
        vm.prank(buyer);
        _expectInvalidStatus(id, IEscrowVault.Status.Funded);
        vault.claimTimeoutRefund(id);
    }

    function test_RevertWhen_ClaimTimeoutTwice() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.warp(vault.getEscrow(id).arbitrationDeadline + 1);
        vm.startPrank(buyer);
        vault.claimTimeoutRefund(id);
        _expectInvalidStatus(id, IEscrowVault.Status.Refunded);
        vault.claimTimeoutRefund(id);
        vm.stopPrank();
    }
}
