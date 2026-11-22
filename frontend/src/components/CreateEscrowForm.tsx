"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { isAddress, parseUnits, type Address } from "viem";
import { useAccount } from "wagmi";

import { TxStatus } from "@/components/TxStatus";
import { NATIVE_TOKEN } from "@/constants/addresses";
import { useCreateEscrow } from "@/hooks/useCreateEscrow";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";
import { useVaultParams } from "@/hooks/useVaultParams";
import { bpsToPercent } from "@/lib/format";

/** Form tạo escrow (người tạo = người mua). Với USDC: bước 1 approve, bước 2 tạo escrow. */
export function CreateEscrowForm() {
  const { address, isConnected } = useAccount();
  const { deployment } = useVaultDeployment();
  const { feeBps, defaultArbiter, paused, usdcAllowed } = useVaultParams();

  const [asset, setAsset] = useState<"ETH" | "USDC">("ETH");
  const [seller, setSeller] = useState("");
  const [amount, setAmount] = useState("");
  const [days, setDays] = useState(7);
  const [arbiter, setArbiter] = useState("");

  useEffect(() => {
    if (defaultArbiter && !arbiter) setArbiter(defaultArbiter);
  }, [defaultArbiter, arbiter]);

  const token: Address = asset === "ETH" ? NATIVE_TOKEN : (deployment?.usdc ?? NATIVE_TOKEN);
  const decimals = asset === "ETH" ? 18 : 6;
  const parsedAmount = useMemo(() => {
    try {
      return amount ? parseUnits(amount, decimals) : 0n;
    } catch {
      return 0n;
    }
  }, [amount, decimals]);

  const { needsApproval, approve, approveTx, create, createTx, createdId } = useCreateEscrow(token, parsedAmount);

  const problems: string[] = [];
  if (seller && !isAddress(seller)) problems.push("Địa chỉ người bán không hợp lệ.");
  if (seller && address && seller.toLowerCase() === address.toLowerCase()) problems.push("Người bán phải khác ví của bạn.");
  if (arbiter && !isAddress(arbiter)) problems.push("Địa chỉ trọng tài không hợp lệ.");
  if (amount && parsedAmount === 0n) problems.push("Số tiền không hợp lệ.");
  if (days < 1 || days > 90) problems.push("Thời hạn giao hàng phải từ 1 đến 90 ngày.");
  if (asset === "USDC" && usdcAllowed === false) problems.push("USDC chưa được whitelist trên mạng này.");

  const ready =
    isConnected && !!deployment && !paused && isAddress(seller) && isAddress(arbiter) && parsedAmount > 0n && problems.length === 0;
  const busy = approveTx.isPending || approveTx.isConfirming || createTx.isPending || createTx.isConfirming;

  async function onSubmit() {
    if (!ready || feeBps === undefined) return;
    if (needsApproval) {
      await approve().catch(() => undefined);
      return;
    }
    await create({
      seller: seller as Address,
      token,
      amount: parsedAmount,
      deliveryDays: days,
      arbiter: arbiter as Address,
      maxFeeBps: feeBps,
    }).catch(() => undefined);
  }

  return (
    <section className="card">
      <h2>Tạo escrow (bạn là người mua)</h2>
      <div className="row">
        {(["ETH", "USDC"] as const).map((a) => (
          <label key={a} className="radio">
            <input type="radio" checked={asset === a} onChange={() => setAsset(a)} /> {a}
          </label>
        ))}
      </div>
      <label className="field">
        Ví người bán
        <input value={seller} onChange={(e) => setSeller(e.target.value.trim())} placeholder="0x…" />
      </label>
      <label className="field">
        Số tiền ({asset})
        <input value={amount} onChange={(e) => setAmount(e.target.value.trim())} placeholder={asset === "ETH" ? "0.01" : "10"} />
      </label>
      <label className="field">
        Thời hạn giao hàng (ngày, 1–90)
        <input type="number" min={1} max={90} value={days} onChange={(e) => setDays(Number(e.target.value))} />
      </label>
      <label className="field">
        Trọng tài (mặc định: trọng tài hệ thống)
        <input value={arbiter} onChange={(e) => setArbiter(e.target.value.trim())} placeholder="0x…" />
      </label>
      <p className="muted">
        Phí hiện hành: <strong>{feeBps !== undefined ? bpsToPercent(feeBps) : "…"}</strong>, trừ vào phần người bán nhận.
        Giao dịch tự hủy nếu admin đổi phí cao hơn mức này trước khi giao dịch vào block.
      </p>
      {problems.map((p) => (
        <p key={p} className="status error">
          {p}
        </p>
      ))}
      <button className="btn primary" disabled={!ready || busy} onClick={onSubmit}>
        {needsApproval ? "Bước 1/2: Cho phép vault dùng USDC (approve)" : "Nạp tiền ký quỹ"}
      </button>
      <TxStatus tx={approveTx} successText="Đã approve. Bấm lại nút để nạp tiền ký quỹ." />
      <TxStatus tx={createTx} successText="Đã tạo escrow." />
      {createdId !== undefined && (
        <p className="status success">
          Mã escrow: <Link href={`/escrow/${createdId.toString()}`}>#{createdId.toString()} → mở chi tiết</Link>
        </p>
      )}
    </section>
  );
}
