import type { Address } from "viem";

/** Khớp enum `IEscrowVault.Status` trong contract. */
export enum EscrowStatus {
  None = 0,
  Funded = 1,
  Delivered = 2,
  Disputed = 3,
  Released = 4,
  Refunded = 5,
  Resolved = 6,
}

export const STATUS_LABEL: Record<EscrowStatus, string> = {
  [EscrowStatus.None]: "Không tồn tại",
  [EscrowStatus.Funded]: "Đã nạp tiền",
  [EscrowStatus.Delivered]: "Đã giao hàng",
  [EscrowStatus.Disputed]: "Đang tranh chấp",
  [EscrowStatus.Released]: "Đã giải ngân",
  [EscrowStatus.Refunded]: "Đã hoàn tiền",
  [EscrowStatus.Resolved]: "Đã phân xử",
};

/** Dữ liệu escrow đọc từ `getEscrow(id)`. */
export type Escrow = {
  buyer: Address;
  deliveryDeadline: number;
  feeBps: number;
  status: EscrowStatus;
  seller: Address;
  disputeDeadline: number;
  arbiter: Address;
  arbitrationDeadline: number;
  token: Address;
  amount: bigint;
};

export type Role = "buyer" | "seller" | "arbiter" | "viewer";

/** Tên hàm ghi của contract dùng trong UI. */
export type EscrowAction =
  | "markDelivered"
  | "release"
  | "refund"
  | "raiseDispute"
  | "resolveDispute"
  | "claimTimeoutRefund";

export type TokenInfo = { address: Address; symbol: string; decimals: number; isNative: boolean };
