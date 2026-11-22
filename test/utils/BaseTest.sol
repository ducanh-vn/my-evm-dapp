// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {EscrowVault} from "../../src/EscrowVault.sol";
import {IEscrowVault} from "../../src/interfaces/IEscrowVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Setup dùng chung: vault, token 6 decimals, các actor và helper tạo escrow.
abstract contract BaseTest is Test {
    EscrowVault internal vault;
    MockERC20 internal usdc;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal defaultArbiter = makeAddr("defaultArbiter");
    address internal buyer = makeAddr("buyer");
    address internal seller = makeAddr("seller");
    address internal arbiter = makeAddr("arbiter");
    address internal stranger = makeAddr("stranger");

    address internal constant ETH = address(0);
    uint16 internal constant FEE_BPS = 100;
    uint48 internal constant PERIOD = 7 days;
    uint256 internal constant AMOUNT = 1_000e6;
    uint256 internal constant ETH_AMOUNT = 1 ether;

    function setUp() public virtual {
        // Chạy ở mốc thời gian thực tế để tránh deadline gần 0.
        vm.warp(1_700_000_000);

        usdc = new MockERC20();
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        vault = new EscrowVault(owner, feeRecipient, defaultArbiter, FEE_BPS, tokens);

        usdc.mint(buyer, 1_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(vault), type(uint256).max);
        vm.deal(buyer, 1_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createUsdc() internal returns (uint256 id) {
        vm.prank(buyer);
        id = vault.createEscrow(seller, address(usdc), AMOUNT, PERIOD, arbiter);
    }

    function _createEth() internal returns (uint256 id) {
        vm.prank(buyer);
        id = vault.createEscrow{value: ETH_AMOUNT}(seller, ETH, ETH_AMOUNT, PERIOD, arbiter);
    }

    function _deliver(uint256 id) internal {
        vm.prank(seller);
        vault.markDelivered(id);
    }

    function _dispute(uint256 id, address by) internal {
        vm.prank(by);
        vault.raiseDispute(id);
    }

    function _status(uint256 id) internal view returns (IEscrowVault.Status) {
        return vault.getEscrow(id).status;
    }

    function _fee(uint256 amount) internal pure returns (uint256) {
        return amount * FEE_BPS / 10_000;
    }

    function _expectInvalidStatus(uint256 id, IEscrowVault.Status current) internal {
        vm.expectRevert(abi.encodeWithSelector(IEscrowVault.InvalidStatus.selector, id, current));
    }
}
