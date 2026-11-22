"use client";

import { useState } from "react";
import { isAddress, type Address } from "viem";
import { useAccount } from "wagmi";

import { TxStatus } from "@/components/TxStatus";
import { NATIVE_TOKEN } from "@/constants/addresses";
import { useBalances } from "@/hooks/useBalances";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";
import { useWithdraw } from "@/hooks/useWithdraw";
import { formatAmount } from "@/lib/format";

/** Số dư ví và số dư chờ rút trong vault; nút Rút tiền (về ví mình hoặc sang ví khác). */
export function BalancesPanel() {
  const { address } = useAccount();
  const { deployment } = useVaultDeployment();
  const b = useBalances(address);
  const { withdraw, tx } = useWithdraw();
  const [to, setTo] = useState("");

  if (!address) return null;
  const toAddr = to && isAddress(to) ? (to as Address) : undefined;
  const busy = tx.isPending || tx.isConfirming;

  const rows: { label: string; wallet?: bigint; pending?: bigint; decimals: number; token?: Address }[] = [
    { label: "ETH", wallet: b.walletEth, pending: b.pendingEth, decimals: 18, token: NATIVE_TOKEN },
    { label: "USDC", wallet: b.walletUsdc, pending: b.pendingUsdc, decimals: 6, token: deployment?.usdc },
  ];

  async function onWithdraw(token?: Address) {
    if (!token) return;
    await withdraw(token, toAddr).catch(() => undefined);
    b.refetch();
  }

  return (
    <section className="card">
      <h2>Số dư của bạn</h2>
      <table className="kv">
        <thead>
          <tr>
            <th>Tài sản</th>
            <th>Trong ví</th>
            <th>Chờ rút trong vault</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.label}>
              <td>{r.label}</td>
              <td>{r.wallet !== undefined ? formatAmount(r.wallet, r.decimals, 4) : "—"}</td>
              <td>
                <strong>{r.pending !== undefined ? formatAmount(r.pending, r.decimals) : "—"}</strong>
              </td>
              <td>
                <button className="btn small primary" disabled={busy || !r.pending} onClick={() => onWithdraw(r.token)}>
                  Rút tiền
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <label className="field">
        Rút sang ví khác (tùy chọn, để trống = về ví đang kết nối)
        <input value={to} onChange={(e) => setTo(e.target.value.trim())} placeholder="0x…" />
      </label>
      {to && !toAddr && <p className="status error">Địa chỉ ví nhận không hợp lệ.</p>}
      <p className="muted">
        Tiền từ escrow không vào ví ngay: được ghi vào &quot;Chờ rút&quot;, bạn bấm Rút tiền để chuyển về ví.
      </p>
      <TxStatus tx={tx} successText="Đã rút tiền." />
    </section>
  );
}
