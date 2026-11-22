// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";
import {EscrowVault} from "../src/EscrowVault.sol";
import {FeeOnTransferERC20} from "./mocks/FeeOnTransferERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract EscrowVaultCreateTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsState() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.defaultArbiter(), defaultArbiter);
        assertEq(vault.feeBps(), FEE_BPS);
        assertTrue(vault.isTokenAllowed(address(usdc)));
        assertEq(vault.nextEscrowId(), 0);
    }

    function test_Constructor_RevertsOnBadParams() public {
        address[] memory none = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new EscrowVault(address(0), feeRecipient, defaultArbiter, FEE_BPS, none);

        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        new EscrowVault(owner, address(0), defaultArbiter, FEE_BPS, none);

        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        new EscrowVault(owner, feeRecipient, address(0), FEE_BPS, none);

        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.FeeTooHigh.selector, uint16(501)));
        new EscrowVault(owner, feeRecipient, defaultArbiter, 501, none);

        address[] memory bad = new address[](1);
        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        new EscrowVault(owner, feeRecipient, defaultArbiter, FEE_BPS, bad);
    }

    /*//////////////////////////////////////////////////////////////
                              HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_CreateUsdc_StoresEscrowAndPullsTokens() public {
        uint48 expectedDeadline = uint48(block.timestamp) + PERIOD;
        vm.expectEmit(address(vault));
        emit IEscrowVault.EscrowCreated(1, buyer, seller, address(usdc), arbiter, AMOUNT, FEE_BPS, expectedDeadline);
        uint256 id = _createUsdc();

        assertEq(id, 1);
        assertEq(vault.nextEscrowId(), 1);
        assertEq(usdc.balanceOf(address(vault)), AMOUNT);

        IEscrowVault.Escrow memory e = vault.getEscrow(id);
        assertEq(e.buyer, buyer);
        assertEq(e.seller, seller);
        assertEq(e.arbiter, arbiter);
        assertEq(e.token, address(usdc));
        assertEq(e.amount, AMOUNT);
        assertEq(e.feeBps, FEE_BPS);
        assertEq(e.deliveryDeadline, expectedDeadline);
        assertEq(e.disputeDeadline, 0);
        assertEq(e.arbitrationDeadline, 0);
        assertEq(uint8(e.status), uint8(IEscrowVault.Status.Funded));
    }

    function test_CreateEth_HoldsEth() public {
        uint256 id = _createEth();
        assertEq(address(vault).balance, ETH_AMOUNT);
        assertEq(vault.getEscrow(id).token, ETH);
    }

    function test_Create_ZeroArbiterUsesDefault_AndIsFrozen() public {
        vm.prank(buyer);
        uint256 id = vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, address(0), MAX_FEE);
        assertEq(vault.getEscrow(id).arbiter, defaultArbiter);

        vm.prank(owner);
        vault.setDefaultArbiter(makeAddr("newDefault"));
        assertEq(vault.getEscrow(id).arbiter, defaultArbiter, "old escrow keeps arbiter");
    }

    function test_Create_FeeLockedAtCreation() public {
        uint256 id = _createUsdc();
        vm.prank(owner);
        vault.setFeeBps(500);
        assertEq(vault.getEscrow(id).feeBps, FEE_BPS);

        vm.prank(buyer);
        vault.release(id);
        assertEq(vault.withdrawable(feeRecipient, address(usdc)), _fee(AMOUNT));
    }

    function test_Create_DeliveryPeriodBounds() public {
        vm.startPrank(buyer);
        vault.createEscrow(seller, address(usdc), AMOUNT, 1 days, arbiter, MAX_FEE);
        vault.createEscrow(seller, address(usdc), AMOUNT, 90 days, arbiter, MAX_FEE);
        vm.stopPrank();
        assertEq(vault.nextEscrowId(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_AmountZero() public {
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.ZeroAmount.selector);
        vault.createEscrow(seller, address(usdc), 0, PERIOD, arbiter, MAX_FEE);
    }

    function test_RevertWhen_SellerZeroOrBuyer() public {
        vm.startPrank(buyer);
        vm.expectRevert(IEscrowVault.ZeroAddress.selector);
        vault.createEscrow(address(0), address(usdc), AMOUNT, PERIOD, arbiter, MAX_FEE);
        vm.expectRevert(IEscrowVault.InvalidSeller.selector);
        vault.createEscrow(buyer, address(usdc), AMOUNT, PERIOD, arbiter, MAX_FEE);
        vm.stopPrank();
    }

    function test_RevertWhen_DeliveryPeriodOutOfRange() public {
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidDeliveryPeriod.selector, uint48(1 days - 1)));
        vault.createEscrow(seller, address(usdc), AMOUNT, 1 days - 1, arbiter, MAX_FEE);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidDeliveryPeriod.selector, uint48(90 days + 1)));
        vault.createEscrow(seller, address(usdc), AMOUNT, 90 days + 1, arbiter, MAX_FEE);
        vm.stopPrank();
    }

    function test_RevertWhen_ArbiterIsBuyerOrSeller() public {
        vm.startPrank(buyer);
        vm.expectRevert(IEscrowVault.InvalidArbiter.selector);
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, buyer, MAX_FEE);
        vm.expectRevert(IEscrowVault.InvalidArbiter.selector);
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, seller, MAX_FEE);
        vm.stopPrank();
    }

    function test_RevertWhen_DefaultArbiterIsParty() public {
        vm.prank(owner);
        vault.setDefaultArbiter(seller);
        vm.prank(buyer);
        vm.expectRevert(IEscrowVault.InvalidArbiter.selector);
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, address(0), MAX_FEE);
    }

    function test_RevertWhen_TokenNotAllowed() public {
        MockERC20 other = new MockERC20();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.TokenNotAllowed.selector, address(other)));
        vault.createEscrow(seller, address(other), AMOUNT, PERIOD, arbiter, MAX_FEE);
    }

    function test_RevertWhen_TokenRemovedFromAllowlist() public {
        uint256 oldId = _createUsdc();
        vm.prank(owner);
        vault.setTokenAllowed(address(usdc), false);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.TokenNotAllowed.selector, address(usdc)));
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter, MAX_FEE);

        // Escrow cũ vẫn hoàn tất và rút được.
        vm.prank(buyer);
        vault.release(oldId);
        vm.prank(seller);
        vault.withdraw(address(usdc));
        assertEq(usdc.balanceOf(seller), AMOUNT - _fee(AMOUNT));
    }

    function test_RevertWhen_EthWrongMsgValue() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidMsgValue.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        vault.createEscrow{value: ETH_AMOUNT - 1}(seller, ETH, ETH_AMOUNT, PERIOD, arbiter, MAX_FEE);
    }

    function test_RevertWhen_Erc20WithMsgValue() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidMsgValue.selector, 0, 1));
        vault.createEscrow{value: 1}(seller, address(usdc), AMOUNT, PERIOD, arbiter, MAX_FEE);
    }

    function test_RevertWhen_Paused() public {
        vm.prank(owner);
        vault.pause();
        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter, MAX_FEE);
    }

    function test_RevertWhen_FeeOnTransferToken() public {
        FeeOnTransferERC20 fot = new FeeOnTransferERC20();
        vm.prank(owner);
        vault.setTokenAllowed(address(fot), true);
        fot.mint(buyer, AMOUNT);
        vm.startPrank(buyer);
        fot.approve(address(vault), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.AmountMismatch.selector, AMOUNT, AMOUNT - AMOUNT / 100));
        vault.createEscrow(seller, address(fot), AMOUNT, PERIOD, arbiter, MAX_FEE);
        vm.stopPrank();
        assertEq(vault.nextEscrowId(), 0, "state rolled back");
    }

    /*//////////////////////////////////////////////////////////////
                  DELIVERY DURATION (1 NGÀY – 90 NGÀY)
    //////////////////////////////////////////////////////////////*/

    function test_DeliveryDurationConstants() public view {
        assertEq(vault.MIN_DELIVERY_DURATION(), 1 days);
        assertEq(vault.MAX_DELIVERY_DURATION(), 90 days);
    }

    function test_DeliveryDuration_ExactlyOneDayOk() public {
        vm.prank(buyer);
        uint256 id = vault.createEscrow(seller, address(usdc), AMOUNT, 1 days, arbiter, MAX_FEE);
        assertEq(vault.getEscrow(id).deliveryDeadline, block.timestamp + 1 days);
    }

    function test_RevertWhen_DeliveryDurationOneDayMinusOneSecond() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidDeliveryPeriod.selector, uint48(1 days - 1)));
        vault.createEscrow(seller, address(usdc), AMOUNT, 1 days - 1, arbiter, MAX_FEE);
    }

    function test_RevertWhen_DeliveryDurationOneHour() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidDeliveryPeriod.selector, uint48(1 hours)));
        vault.createEscrow(seller, address(usdc), AMOUNT, 1 hours, arbiter, MAX_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                         AUDIT L-1: maxFeeBps
    //////////////////////////////////////////////////////////////*/

    function test_MaxFee_EqualToCurrentFeeOk() public {
        vm.prank(buyer);
        uint256 id = vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter, FEE_BPS);
        assertEq(vault.getEscrow(id).feeBps, FEE_BPS);
    }

    function test_RevertWhen_CurrentFeeAboveMax() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.FeeExceedsMax.selector, FEE_BPS, FEE_BPS - 1));
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter, FEE_BPS - 1);
    }

    function test_MaxFee_ZeroAcceptedWhenFeeZero() public {
        vm.prank(owner);
        vault.setFeeBps(0);
        vm.prank(buyer);
        uint256 id = vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter, 0);
        assertEq(vault.getEscrow(id).feeBps, 0);
    }

    /// @dev Kịch bản L-1: UI hiển thị 1%, admin đổi phí lên 5% đúng lúc giao dịch của Buyer đang chờ.
    function test_MaxFee_ProtectsAgainstAdminFeeChangeRace() public {
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);

        vm.prank(owner);
        vault.setFeeBps(500); // vào block trước giao dịch của Buyer

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.FeeExceedsMax.selector, uint16(500), FEE_BPS));
        vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter, FEE_BPS);

        assertEq(vault.nextEscrowId(), 0, "no escrow created");
        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore, "no funds pulled");
    }

    function test_RevertWhen_CurrentFeeAboveMax_Eth() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.FeeExceedsMax.selector, FEE_BPS, uint16(0)));
        vault.createEscrow{value: ETH_AMOUNT}(seller, ETH, ETH_AMOUNT, PERIOD, arbiter, 0);
    }

    function test_RevertWhen_PlainEthSent() public {
        vm.prank(buyer);
        (bool ok,) = address(vault).call{value: 1}("");
        assertFalse(ok);
    }
}
