// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";

contract EscrowVaultReleaseTest is BaseTest {
    function test_HappyPath_Usdc_DeliverReleaseWithdraw() public {
        uint256 id = _createUsdc();
        _deliver(id);

        uint256 fee = _fee(AMOUNT);
        vm.expectEmit(address(vault));
        emit IEscrowVault.EscrowReleased(id, buyer, AMOUNT - fee, fee);
        vm.prank(buyer);
        vault.release(id);

        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Released));
        assertEq(vault.withdrawable(seller, address(usdc)), AMOUNT - fee);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), fee);

        vm.prank(seller);
        vault.withdraw(address(usdc));
        vm.prank(feeRecipient);
        vault.withdraw(address(usdc));
        assertEq(usdc.balanceOf(seller), AMOUNT - fee);
        assertEq(usdc.balanceOf(feeRecipient), fee);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_HappyPath_Eth_DeliverReleaseWithdraw() public {
        uint256 id = _createEth();
        _deliver(id);
        vm.prank(buyer);
        vault.release(id);

        uint256 fee = _fee(ETH_AMOUNT);
        vm.prank(seller);
        vault.withdraw(ETH);
        vm.prank(feeRecipient);
        vault.withdraw(ETH);
        assertEq(seller.balance, ETH_AMOUNT - fee);
        assertEq(feeRecipient.balance, fee);
        assertEq(address(vault).balance, 0);
    }

    function test_BuyerReleaseWhileFunded() public {
        uint256 id = _createUsdc();
        vm.prank(buyer);
        vault.release(id);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Released));
    }

    function test_SellerAutoReleaseAfterDisputeWindow() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.warp(vault.getEscrow(id).disputeDeadline + 1);
        vm.prank(seller);
        vault.release(id);
        assertEq(vault.withdrawable(seller, address(usdc)), AMOUNT - _fee(AMOUNT));
    }

    function test_FeeRecipientReadAtSettlement() public {
        uint256 id = _createUsdc();
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        vault.setFeeRecipient(newRecipient);
        vm.prank(buyer);
        vault.release(id);
        assertEq(vault.withdrawable(newRecipient, address(usdc)), _fee(AMOUNT));
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), 0);
    }

    function test_ZeroFee_NoFeeCredit() public {
        vm.prank(owner);
        vault.setFeeBps(0);
        uint256 id = _createUsdc();
        vm.prank(buyer);
        vault.release(id);
        assertEq(vault.withdrawable(seller, address(usdc)), AMOUNT);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                             MARK DELIVERED
    //////////////////////////////////////////////////////////////*/

    function test_MarkDelivered_SetsDisputeDeadline() public {
        uint256 id = _createUsdc();
        uint48 expected = uint48(block.timestamp) + 3 days;
        vm.expectEmit(address(vault));
        emit IEscrowVault.EscrowDelivered(id, expected);
        _deliver(id);
        assertEq(vault.getEscrow(id).disputeDeadline, expected);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Delivered));
    }

    function test_MarkDelivered_AtDeadlineOk() public {
        uint256 id = _createUsdc();
        vm.warp(vault.getEscrow(id).deliveryDeadline);
        _deliver(id);
    }

    function test_RevertWhen_MarkDeliveredByNonSeller() public {
        uint256 id = _createUsdc();
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.Unauthorized.selector);
        vault.markDelivered(id);
    }

    function test_RevertWhen_MarkDeliveredAfterDeadline() public {
        uint256 id = _createUsdc();
        vm.warp(vault.getEscrow(id).deliveryDeadline + 1);
        vm.prank(seller);
        vm.expectRevert(IEscrowVault.DeadlinePassed.selector);
        vault.markDelivered(id);
    }

    function test_RevertWhen_MarkDeliveredTwice() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.prank(seller);
        _expectInvalidStatus(id, IEscrowVault.Status.Delivered);
        vault.markDelivered(id);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_SellerReleaseBeforeWindowEnds() public {
        uint256 id = _createUsdc();
        _deliver(id);
        vm.warp(vault.getEscrow(id).disputeDeadline);
        vm.prank(seller);
        vm.expectRevert(IEscrowVault.DeadlineNotReached.selector);
        vault.release(id);
    }

    function test_RevertWhen_SellerReleaseWhileFunded() public {
        uint256 id = _createUsdc();
        vm.prank(seller);
        _expectInvalidStatus(id, IEscrowVault.Status.Funded);
        vault.release(id);
    }

    function test_RevertWhen_StrangerRelease() public {
        uint256 id = _createUsdc();
        vm.prank(stranger);
        vm.expectRevert(IEscrowVault.Unauthorized.selector);
        vault.release(id);
    }

    function test_RevertWhen_BuyerReleaseWhileDisputed() public {
        uint256 id = _createUsdc();
        _dispute(id, buyer);
        vm.prank(buyer);
        _expectInvalidStatus(id, IEscrowVault.Status.Disputed);
        vault.release(id);
    }

    function test_RevertWhen_DoubleRelease() public {
        uint256 id = _createUsdc();
        vm.startPrank(buyer);
        vault.release(id);
        _expectInvalidStatus(id, IEscrowVault.Status.Released);
        vault.release(id);
        vm.stopPrank();
    }
}
