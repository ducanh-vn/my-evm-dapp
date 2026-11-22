import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError } from "viem";

/** Thông điệp dễ hiểu cho từng Custom Error của EscrowVault. */
const CONTRACT_ERRORS: Record<string, string> = {
  ZeroAddress: "Địa chỉ không được để trống (0x0).",
  ZeroAmount: "Số tiền phải lớn hơn 0.",
  InvalidSeller: "Người bán không hợp lệ (không được trùng người mua).",
  InvalidArbiter: "Trọng tài phải khác người mua và người bán.",
  InvalidDeliveryPeriod: "Thời hạn giao hàng phải từ 1 đến 90 ngày.",
  TokenNotAllowed: "Token này chưa được whitelist.",
  InvalidMsgValue: "Số ETH gửi kèm không khớp số tiền.",
  AmountMismatch: "Số token thực nhận không khớp (token có phí chuyển?).",
  EscrowNotFound: "Không tìm thấy escrow.",
  InvalidStatus: "Escrow không ở trạng thái cho phép thao tác này.",
  Unauthorized: "Ví đang kết nối không có quyền thực hiện thao tác này.",
  DeadlinePassed: "Đã quá hạn cho thao tác này.",
  DeadlineNotReached: "Chưa tới thời điểm được phép.",
  InvalidBps: "Tỷ lệ phải trong khoảng 0–100%.",
  FeeTooHigh: "Phí vượt trần 5%.",
  FeeExceedsMax: "Phí hiện hành cao hơn mức phí tối đa bạn chấp nhận (admin vừa đổi phí?).",
  NothingToWithdraw: "Không có số dư để rút.",
  EthTransferFailed: "Ví nhận không nhận được ETH.",
  EnforcedPause: "Contract đang tạm dừng tạo escrow mới.",
  ReentrancyGuardReentrantCall: "Giao dịch bị chặn do gọi lồng (reentrancy).",
};

/** Chuyển lỗi wagmi/viem thành câu tiếng Việt; tách riêng trường hợp người dùng từ chối ký. */
export function parseTxError(error: unknown): string | undefined {
  if (!error) return undefined;
  if (error instanceof BaseError) {
    if (error.walk((e) => e instanceof UserRejectedRequestError)) {
      return "Bạn đã từ chối ký giao dịch trong ví.";
    }
    const revert = error.walk((e) => e instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName ?? "";
      return CONTRACT_ERRORS[name] ?? `Contract từ chối: ${name || revert.shortMessage}`;
    }
    return error.shortMessage;
  }
  return error instanceof Error ? error.message : String(error);
}
