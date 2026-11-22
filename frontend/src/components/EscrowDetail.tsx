"use client";

import { useAccount } from "wagmi";

import { EscrowActions } from "@/components/EscrowActions";
import { useChainTime } from "@/hooks/useChainTime";
import { useEscrow } from "@/hooks/useEscrow";
import { useTokenInfo } from "@/hooks/useTokenInfo";
import { disputeWindowEnd, roleOf } from "@/lib/escrowRules";
import { bpsToPercent, formatAmount, formatCountdown, formatDateTime, shortAddress } from "@/lib/format";
import { EscrowStatus, STATUS_LABEL } from "@/types/escrow";

/** Chi tiết một escrow: các bên, số tiền, các mốc thời gian (đếm theo giờ chain) và nút thao tác. */
export function EscrowDetail({ id }: { id: bigint }) {
  const { address } = useAccount();
  const now = useChainTime();
  const { escrow, isLoading, error, refetch } = useEscrow(id);
  const token = useTokenInfo(escrow?.token);

  if (isLoading) return <section className="card">Đang tải escrow #{id.toString()}…</section>;
  if (error) return <section className="card status error">Không đọc được escrow: {error.message}</section>;
  if (!escrow || escrow.status === EscrowStatus.None)
    return <section className="card">Không tìm thấy escrow #{id.toString()} trên mạng này.</section>;

  const role = roleOf(escrow, address);
  const amountText = token ? `${formatAmount(escrow.amount, token.decimals)} ${token.symbol}` : "…";
  const deadlines: { label: string; at: number; show: boolean }[] = [
    { label: "Hạn giao hàng", at: escrow.deliveryDeadline, show: true },
    { label: "Hạn khiếu nại (3 ngày sau báo giao)", at: escrow.disputeDeadline, show: escrow.disputeDeadline > 0 },
    {
      label: "Người bán tự giải ngân được sau",
      at: disputeWindowEnd(escrow),
      show: escrow.status === EscrowStatus.Delivered,
    },
    { label: "Hạn trọng tài phân xử (14 ngày)", at: escrow.arbitrationDeadline, show: escrow.arbitrationDeadline > 0 },
  ];

  return (
    <>
      <section className="card">
        <h2>
          Escrow #{id.toString()} <span className={`badge status-${escrow.status}`}>{STATUS_LABEL[escrow.status as EscrowStatus]}</span>
        </h2>
        <table className="kv">
          <tbody>
            <tr>
              <th>Số tiền</th>
              <td>
                <strong>{amountText}</strong> — phí {bpsToPercent(escrow.feeBps)} (đã chốt lúc tạo)
              </td>
            </tr>
            <tr>
              <th>Người mua</th>
              <td title={escrow.buyer}>{shortAddress(escrow.buyer)}</td>
            </tr>
            <tr>
              <th>Người bán</th>
              <td title={escrow.seller}>{shortAddress(escrow.seller)}</td>
            </tr>
            <tr>
              <th>Trọng tài</th>
              <td title={escrow.arbiter}>{shortAddress(escrow.arbiter)}</td>
            </tr>
            {deadlines
              .filter((d) => d.show)
              .map((d) => (
                <tr key={d.label}>
                  <th>{d.label}</th>
                  <td>
                    {formatDateTime(d.at)} <span className="muted">({formatCountdown(d.at, now)})</span>
                  </td>
                </tr>
              ))}
          </tbody>
        </table>
      </section>
      <EscrowActions id={id} escrow={escrow} role={role} now={now} onDone={() => void refetch()} />
    </>
  );
}
