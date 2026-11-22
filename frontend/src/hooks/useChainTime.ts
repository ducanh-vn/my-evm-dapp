"use client";

import { useBlock } from "wagmi";

/**
 * Thời gian theo block mới nhất của chain (giây). Dùng thay đồng hồ máy để đếm ngược,
 * vì trên Anvil thời gian chain có thể được tua nhanh.
 */
export function useChainTime(): number {
  const { data: block } = useBlock({ watch: true });
  return block ? Number(block.timestamp) : Math.floor(Date.now() / 1000);
}
