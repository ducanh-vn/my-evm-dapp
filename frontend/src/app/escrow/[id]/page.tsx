"use client";

import Link from "next/link";
import { use } from "react";

import { BalancesPanel } from "@/components/BalancesPanel";
import { EscrowDetail } from "@/components/EscrowDetail";
import { TimeTravelPanel } from "@/components/TimeTravelPanel";

export default function EscrowPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const valid = /^\d+$/.test(id) && BigInt(id) > 0n;

  return (
    <div className="grid">
      <div className="col">
        <Link href="/">← Về trang chính</Link>
        {valid ? <EscrowDetail id={BigInt(id)} /> : <section className="card">Mã escrow không hợp lệ.</section>}
      </div>
      <div className="col">
        <BalancesPanel />
        <TimeTravelPanel />
      </div>
    </div>
  );
}
