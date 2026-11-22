import { formatUnits, type Address } from "viem";

export function shortAddress(addr?: Address | string): string {
  if (!addr) return "—";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function formatAmount(value: bigint, decimals: number, maxFraction = 6): string {
  const s = formatUnits(value, decimals);
  const [int, frac = ""] = s.split(".");
  const trimmed = frac.slice(0, maxFraction).replace(/0+$/, "");
  return trimmed ? `${int}.${trimmed}` : int;
}

export function formatDateTime(unixSeconds: number): string {
  if (!unixSeconds) return "—";
  return new Date(unixSeconds * 1000).toLocaleString("vi-VN");
}

/** Đếm ngược tới `deadline` theo thời gian chain `now` (không dùng đồng hồ máy). */
export function formatCountdown(deadline: number, now: number): string {
  if (!deadline) return "—";
  const diff = deadline - now;
  if (diff <= 0) return "đã qua";
  const d = Math.floor(diff / 86_400);
  const h = Math.floor((diff % 86_400) / 3_600);
  const m = Math.floor((diff % 3_600) / 60);
  if (d > 0) return `còn ${d} ngày ${h} giờ`;
  if (h > 0) return `còn ${h} giờ ${m} phút`;
  return `còn ${m} phút ${diff % 60} giây`;
}

export function bpsToPercent(bps: number): string {
  return `${(bps / 100).toLocaleString("vi-VN", { maximumFractionDigits: 2 })}%`;
}
