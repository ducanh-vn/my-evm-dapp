// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./utils/BaseTest.sol";
import {IEscrowVault} from "../src/interfaces/IEscrowVault.sol";
import {EscrowVaultHandler} from "./handlers/EscrowVaultHandler.sol";

/// @notice Kiểm tra các invariant ở mục 3.6 của escrow-vault-spec.md sau mỗi chuỗi lệnh ngẫu nhiên.
contract EscrowVaultInvariantTest is BaseTest {
    EscrowVaultHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new EscrowVaultHandler(vault, usdc, owner);
        targetContract(address(handler));
    }

    function _isOpen(IEscrowVault.Status s) internal pure returns (bool) {
        return
            s == IEscrowVault.Status.Funded || s == IEscrowVault.Status.Delivered || s == IEscrowVault.Status.Disputed;
    }

    /// @dev (1) Số dư thực của contract bằng tiền đang khóa + tổng số dư chờ rút, theo từng tài sản.
    ///      Handler không gửi token/ETH trực tiếp nên phải bằng nhau (spec chỉ yêu cầu ≥).
    function invariant_SolvencyPerToken() public view {
        address[2] memory tokens = [ETH, address(usdc)];
        for (uint256 t; t < 2; ++t) {
            address token = tokens[t];
            uint256 owed;
            uint256 n = handler.idsLength();
            for (uint256 i; i < n; ++i) {
                IEscrowVault.Escrow memory e = vault.getEscrow(handler.ids(i));
                if (e.token == token && _isOpen(e.status)) owed += e.amount;
            }
            uint256 m = handler.actorsLength();
            for (uint256 i; i < m; ++i) {
                owed += vault.withdrawable(handler.actors(i), token);
            }
            owed += vault.withdrawable(handler.initialFeeRecipient(), token);

            uint256 bal = token == ETH ? address(vault).balance : usdc.balanceOf(address(vault));
            assertEq(bal, owed, "solvency");
        }
    }

    /// @dev (2) Escrow đã kết thúc không đổi trạng thái.
    function invariant_TerminalStatusFrozen() public view {
        uint256 n = handler.idsLength();
        for (uint256 i; i < n; ++i) {
            uint256 id = handler.ids(i);
            IEscrowVault.Status recorded = handler.ghostTerminal(id);
            if (recorded != IEscrowVault.Status.None) {
                assertEq(uint8(vault.getEscrow(id).status), uint8(recorded), "terminal changed");
            }
        }
    }

    /// @dev (3) Phí luôn ≤ trần.
    function invariant_FeeCapped() public view {
        assertLe(vault.feeBps(), vault.MAX_FEE_BPS());
        uint256 n = handler.idsLength();
        for (uint256 i; i < n; ++i) {
            assertLe(vault.getEscrow(handler.ids(i)).feeBps, vault.MAX_FEE_BPS());
        }
    }

    /// @dev (5) Thao tác admin không làm giảm số dư chờ rút.
    function invariant_AdminCannotReduceFunds() public view {
        assertFalse(handler.ghostAdminReducedFunds());
    }

    /// @dev (6) Escrow Disputed quá hạn luôn claimTimeoutRefund được.
    function invariant_DisputeAlwaysTerminates() public view {
        assertFalse(handler.ghostTimeoutClaimFailed());
    }

    /// @dev (7) Arbiter của escrow không đổi sau khi tạo.
    function invariant_ArbiterImmutable() public view {
        uint256 n = handler.idsLength();
        for (uint256 i; i < n; ++i) {
            uint256 id = handler.ids(i);
            assertEq(vault.getEscrow(id).arbiter, handler.ghostArbiter(id), "arbiter changed");
        }
    }

    /// @dev Escrow tồn tại luôn có id liên tục từ 1 tới nextEscrowId.
    function invariant_IdsSequential() public view {
        assertEq(vault.nextEscrowId(), handler.idsLength());
    }
}
