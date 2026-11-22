import type { Address } from "viem";

import { EscrowStatus, type Escrow, type EscrowAction, type Role } from "@/types/escrow";

/**
 * Bản sao phía UI của các điều kiện trong EscrowVault.sol, chỉ để ẩn/hiện nút.
 * Contract vẫn là nguồn sự thật: nếu lệch, giao dịch sẽ revert và UI hiện lỗi.
 */

export function roleOf(escrow: Escrow, account?: Address): Role {
  if (!account) return "viewer";
  const a = account.toLowerCase();
  if (a === escrow.buyer.toLowerCase()) return "buyer";
  if (a === escrow.seller.toLowerCase()) return "seller";
  if (a === escrow.arbiter.toLowerCase()) return "arbiter";
  return "viewer";
}

/** Mốc kết thúc khiếu nại của escrow Delivered: max(disputeDeadline, deliveryDeadline) (audit M-1). */
export function disputeWindowEnd(escrow: Escrow): number {
  return Math.max(escrow.disputeDeadline, escrow.deliveryDeadline);
}

export type ActionOption = {
  action: EscrowAction;
  label: string;
  hint: string;
  tone: "primary" | "neutral" | "danger";
};

/** Danh sách thao tác hợp lệ cho `role` tại thời điểm chain `now`. */
export function availableActions(escrow: Escrow, role: Role, now: number): ActionOption[] {
  const s = escrow.status;
  const out: ActionOption[] = [];
  const beforeDelivery = now <= escrow.deliveryDeadline;
  const windowEnd = disputeWindowEnd(escrow);

  const canDispute =
    (s === EscrowStatus.Funded && beforeDelivery) || (s === EscrowStatus.Delivered && now <= windowEnd);

  if (role === "buyer") {
    if (s === EscrowStatus.Funded || s === EscrowStatus.Delivered) {
      out.push({
        action: "release",
        label: "Xác nhận & giải ngân cho người bán",
        hint: "Tiền (trừ phí) được ghi có cho người bán; người bán tự bấm Rút tiền.",
        tone: "primary",
      });
    }
    if (s === EscrowStatus.Funded && !beforeDelivery) {
      out.push({
        action: "refund",
        label: "Lấy lại tiền (quá hạn giao hàng)",
        hint: "Người bán chưa báo giao hàng trước hạn.",
        tone: "neutral",
      });
    }
    if (s === EscrowStatus.Disputed && now > escrow.arbitrationDeadline) {
      out.push({
        action: "claimTimeoutRefund",
        label: "Lấy lại tiền (trọng tài quá 14 ngày)",
        hint: "Trọng tài không phán quyết kịp; hoàn 100%, không phí.",
        tone: "primary",
      });
    }
  }

  if (role === "seller") {
    if (s === EscrowStatus.Funded && beforeDelivery) {
      out.push({
        action: "markDelivered",
        label: "Báo đã giao hàng",
        hint: "Nên bấm trước khi gửi hàng. Người mua được khiếu nại tới hết mốc.",
        tone: "primary",
      });
    }
    if (s === EscrowStatus.Delivered && now > windowEnd) {
      out.push({
        action: "release",
        label: "Tự giải ngân (đã qua hạn khiếu nại)",
        hint: "Đã qua cả hạn khiếu nại lẫn hạn giao hàng.",
        tone: "primary",
      });
    }
    if (s === EscrowStatus.Funded || s === EscrowStatus.Delivered || s === EscrowStatus.Disputed) {
      out.push({
        action: "refund",
        label: "Hoàn toàn bộ tiền cho người mua",
        hint: "Tự nguyện hủy giao dịch; không thu phí.",
        tone: "danger",
      });
    }
  }

  if ((role === "buyer" || role === "seller") && canDispute) {
    out.push({
      action: "raiseDispute",
      label: "Mở tranh chấp",
      hint: "Khóa tiền chờ trọng tài phân xử tối đa 14 ngày.",
      tone: "danger",
    });
  }

  if (role === "arbiter" && s === EscrowStatus.Disputed && now <= escrow.arbitrationDeadline) {
    out.push({
      action: "resolveDispute",
      label: "Phân xử",
      hint: "Chọn tỷ lệ cho người mua; phần còn lại cho người bán (trừ phí).",
      tone: "primary",
    });
  }

  return out;
}

/** Giải thích ngắn khi vai trò hiện tại không có nút nào. */
export function idleReason(escrow: Escrow, role: Role, now: number): string {
  const s = escrow.status;
  if (s >= EscrowStatus.Released) return "Escrow đã kết thúc. Người nhận tiền vào mục Số dư chờ rút để rút.";
  if (role === "viewer") return "Ví đang kết nối không phải người mua, người bán hay trọng tài của escrow này.";
  if (role === "seller" && s === EscrowStatus.Delivered) return "Chờ người mua xác nhận, hoặc chờ qua hạn khiếu nại.";
  if (role === "arbiter" && s !== EscrowStatus.Disputed) return "Chỉ phân xử được khi có tranh chấp.";
  if (role === "arbiter" && now > escrow.arbitrationDeadline) return "Đã quá 14 ngày, không còn phân xử được.";
  if (role === "buyer" && s === EscrowStatus.Disputed) return "Chờ trọng tài phân xử.";
  return "Hiện chưa có thao tác nào cho vai trò này.";
}
