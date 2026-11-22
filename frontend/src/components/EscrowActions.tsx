"use client";

import { useState } from "react";

import { TxStatus } from "@/components/TxStatus";
import { useEscrowAction } from "@/hooks/useEscrowAction";
import { availableActions, idleReason } from "@/lib/escrowRules";
import type { Escrow, EscrowAction, Role } from "@/types/escrow";

const ROLE_LABEL: Record<Role, string> = {
  buyer: "Người mua",
  seller: "Người bán",
  arbiter: "Trọng tài",
  viewer: "Người xem",
};

/** Các nút thao tác hợp lệ theo vai trò của ví đang kết nối và thời gian chain hiện tại. */
export function EscrowActions(props: { id: bigint; escrow: Escrow; role: Role; now: number; onDone: () => void }) {
  const { id, escrow, role, now, onDone } = props;
  const { run, tx } = useEscrowAction();
  const [buyerPercent, setBuyerPercent] = useState(50);
  const options = availableActions(escrow, role, now);
  const busy = tx.isPending || tx.isConfirming;

  async function onClick(action: EscrowAction) {
    if (action === "refund" && role === "seller" && !window.confirm("Hoàn toàn bộ tiền cho người mua?")) return;
    await run(action, id, Math.round(buyerPercent * 100)).catch(() => undefined);
    onDone();
  }

  return (
    <section className="card">
      <h2>Thao tác — bạn là {ROLE_LABEL[role]}</h2>
      {options.length === 0 && <p className="muted">{idleReason(escrow, role, now)}</p>}
      {options.map((o) => (
        <div key={o.action} className="action">
          {o.action === "resolveDispute" && (
            <label className="field">
              Phần cho người mua: <strong>{buyerPercent}%</strong> — người bán: {100 - buyerPercent}% (trừ phí)
              <input type="range" min={0} max={100} step={5} value={buyerPercent} onChange={(e) => setBuyerPercent(Number(e.target.value))} />
            </label>
          )}
          <button className={`btn ${o.tone}`} disabled={busy} onClick={() => onClick(o.action)}>
            {o.label}
          </button>
          <span className="muted"> {o.hint}</span>
        </div>
      ))}
      <TxStatus tx={tx} successText="Đã cập nhật escrow." />
    </section>
  );
}
