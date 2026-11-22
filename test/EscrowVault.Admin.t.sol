// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract EscrowVaultAdminTest is BaseTest {
    function _expectNotOwner() internal {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
    }

    function test_SetFeeBps() public {
        vm.expectEmit(address(vault));
        emit IEscrowVault.FeeUpdated(FEE_BPS, 500);
        vm.prank(owner);
        vault.setFeeBps(500);
        assertEq(vault.feeBps(), 500);
    }

    function test_RevertWhen_SetFeeBpsAboveCap() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.FeeTooHigh.selector, uint16(501)));
        vault.setFeeBps(501);
    }

    function test_SetFeeRecipient() public {
        address r = makeAddr("r");
        vm.expectEmit(address(vault));
        emit IEscrowVault.FeeRecipientUpdated(feeRecipient, r);
        vm.prank(owner);
        vault.setFeeRecipient(r);
        assertEq(vault.feeRecipient(), r);
    }

    function test_SetDefaultArbiter() public {
        address a = makeAddr("a");
        vm.expectEmit(address(vault));
        emit IEscrowVault.DefaultArbiterUpdated(defaultArbiter, a);
        vm.prank(owner);
        vault.setDefaultArbiter(a);
        assertEq(vault.defaultArbiter(), a);
    }

    function test_SetTokenAllowed() public {
        address t = makeAddr("token");
        vm.expectEmit(address(vault));
        emit IEscrowVault.TokenAllowlistUpdated(t, true);
        vm.prank(owner);
        vault.setTokenAllowed(t, true);
        assertTrue(vault.isTokenAllowed(t));
    }

    function test_RevertWhen_AdminSettersZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        vault.setDefaultArbiter(address(0));
        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        vault.setTokenAllowed(address(0), true);
        vm.stopPrank();
    }

    function test_RevertWhen_AdminCalledByStranger() public {
        vm.startPrank(stranger);
        _expectNotOwner();
        vault.setFeeBps(0);
        _expectNotOwner();
        vault.setFeeRecipient(stranger);
        _expectNotOwner();
        vault.setDefaultArbiter(stranger);
        _expectNotOwner();
        vault.setTokenAllowed(stranger, true);
        _expectNotOwner();
        vault.pause();
        _expectNotOwner();
        vault.unpause();
        _expectNotOwner();
        vault.transferOwnership(stranger);
        vm.stopPrank();
    }

    function test_RevertWhen_RenounceOwnership() public {
        vm.prank(owner);
        vm.expectRevert(IEscrowVault.RenounceDisabled.selector);
        vault.renounceOwnership();
        assertEq(vault.owner(), owner);
    }

    function test_TwoStepOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), owner, "not yet transferred");
        assertEq(vault.pendingOwner(), newOwner);

        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                 PAUSE
    //////////////////////////////////////////////////////////////*/

    function test_Pause_OnlyBlocksCreate() public {
        uint256 a = _createUsdc(); // release by buyer
        uint256 b = _createUsdc(); // deliver -> seller auto-release
        uint256 c = _createUsdc(); // refund by seller
        uint256 d = _createUsdc(); // dispute -> resolve
        uint256 f = _createUsdc(); // dispute -> timeout refund
        _deliver(b);

        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter, MAX_FEE);

        vm.prank(buyer);
        vault.release(a);
        vm.prank(seller);
        vault.refund(c);
        _dispute(d, buyer);
        vm.prank(arbiter);
        vault.resolveDispute(d, 5_000);
        _dispute(f, seller);

        vm.warp(block.timestamp + 15 days);
        vm.prank(seller);
        vault.release(b);
        vm.prank(buyer);
        vault.claimTimeoutRefund(f);

        vm.prank(seller);
        vault.withdraw(address(usdc));
        vm.prank(buyer);
        vault.withdraw(address(usdc));

        vm.prank(owner);
        vault.unpause();
        _createUsdc();
    }

    function test_MarkDeliveredWhilePaused() public {
        uint256 id = _createUsdc();
        vm.prank(owner);
        vault.pause();
        _deliver(id);
        assertEq(uint8(_status(id)), uint8(IEscrowVault.Status.Delivered));
    }
}
