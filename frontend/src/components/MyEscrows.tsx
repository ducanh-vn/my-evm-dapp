"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useAccount } from "wagmi";

import { useMyEscrows } from "@/hooks/useMyEscrows";

const ROLE_LABEL = { buyer: "Người mua", seller: "Người bán", arbiter: "Trọng tài" } as const;

/** Tra cứu escrow theo mã và danh sách escrow liên quan tới ví đang kết nối. */
export function MyEscrows() {
  const { address } = useAccount();
  const router = useRouter();
  const [lookup, setLookup] = useState("");
  const { data, isLoading, error } = useMyEscrows(address);

  return (
    <section className="card">
      <h2>Escrow của tôi</h2>
      <div className="row">
        <input
          value={lookup}
          onChange={(e) => setLookup(e.target.value.replace(/\D/g, ""))}
          placeholder="Nhập mã escrow, ví dụ 1"
        />
        <button className="btn" disabled={!lookup} onClick={() => router.push(`/escrow/${lookup}`)}>
          Mở
        </button>
      </div>
      {!address && <p className="muted">Kết nối ví để xem các escrow bạn tham gia.</p>}
      {isLoading && <p className="muted">Đang đọc danh sách escrow…</p>}
      {error && <p className="status error">Không đọc được danh sách: {error.message}</p>}
      {data && data.items.length === 0 && <p className="muted">Chưa có escrow nào liên quan tới ví này.</p>}
      {data && data.total > data.scanned && (
        <p className="muted">
          Chỉ quét {data.scanned} escrow mới nhất trên tổng {data.total}; escrow cũ hơn hãy tra theo mã.
        </p>
      )}
      {data && data.items.length > 0 && (
        <ul className="list">
          {data.items.map((e) => (
            <li key={`${e.id}-${e.role}`}>
              <Link href={`/escrow/${e.id.toString()}`}>Escrow #{e.id.toString()}</Link>{" "}
              <span className="badge">{ROLE_LABEL[e.role]}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
