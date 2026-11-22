"use client";

import type { TxAction } from "@/hooks/useTxAction";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

/** Hiển thị trạng thái giao dịch: chờ ký ví → chờ block → thành công / lỗi. */
export function TxStatus({ tx, successText = "Giao dịch thành công." }: { tx: TxAction; successText?: string }) {
  const { deployment } = useVaultDeployment();
  const link =
    tx.hash && deployment?.explorerUrl ? `${deployment.explorerUrl}/tx/${tx.hash}` : undefined;

  if (tx.isPending) return <p className="status pending">⏳ Đang chờ bạn ký giao dịch trong MetaMask…</p>;
  if (tx.isConfirming)
    return (
      <p className="status pending">
        ⛓️ Đã gửi, đang chờ block xác nhận…{" "}
        {link && (
          <a href={link} target="_blank" rel="noreferrer">
            xem giao dịch
          </a>
        )}
      </p>
    );
  if (tx.errorMessage) return <p className="status error">⚠️ {tx.errorMessage}</p>;
  if (tx.isReverted) return <p className="status error">⚠️ Giao dịch bị revert trên chain.</p>;
  if (tx.isSuccess)
    return (
      <p className="status success">
        ✅ {successText}{" "}
        {link && (
          <a href={link} target="_blank" rel="noreferrer">
            xem giao dịch
          </a>
        )}
      </p>
    );
  return null;
}
