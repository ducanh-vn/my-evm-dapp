"use client";

import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { parseTxError } from "@/lib/errors";

/**
 * Bọc một giao dịch ghi với 2 trạng thái tách biệt:
 * - `isPending`: đang chờ người dùng ký trong ví;
 * - `isConfirming`: đã gửi, đang chờ block xác nhận.
 * Lỗi (từ chối ký, revert) được chuyển thành tiếng Việt qua `parseTxError`.
 */
export function useTxAction() {
  const write = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: write.data });

  const error = write.error ?? receipt.error;
  return {
    writeContractAsync: write.writeContractAsync,
    hash: write.data,
    receipt: receipt.data,
    isPending: write.isPending,
    isConfirming: !!write.data && receipt.isLoading,
    isSuccess: receipt.isSuccess && receipt.data?.status === "success",
    isReverted: receipt.data?.status === "reverted",
    errorMessage: parseTxError(error),
    reset: write.reset,
  };
}

export type TxAction = ReturnType<typeof useTxAction>;
