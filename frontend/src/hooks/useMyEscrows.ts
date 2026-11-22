"use client";

import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { usePublicClient } from "wagmi";

import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

/** Chỉ quét N escrow mới nhất (MVP). Khi nhiều hơn sẽ chuyển sang Indexer (Ponder / The Graph). */
const MAX_SCAN = 200;
/** Số lệnh đọc song song mỗi đợt, tránh dội RPC công khai. */
const BATCH = 20;

export type MyEscrowRef = { id: bigint; role: "buyer" | "seller" | "arbiter" };

/**
 * Danh sách escrow liên quan tới `account`: đọc `nextEscrowId` rồi `getEscrow` cho các id mới nhất.
 * Không dùng eth_getLogs vì RPC Base Sepolia giới hạn mỗi lần chỉ 200 block.
 * Không dùng multicall vì Anvil mặc định không có Multicall3.
 */
export function useMyEscrows(account?: Address) {
  const { deployment, chainId } = useVaultDeployment();
  const client = usePublicClient();

  return useQuery({
    queryKey: ["myEscrows", chainId, deployment?.escrowVault, account],
    enabled: !!client && !!deployment && !!account,
    refetchInterval: 8_000,
    queryFn: async (): Promise<{ items: MyEscrowRef[]; scanned: number; total: number }> => {
      if (!client || !deployment || !account) return { items: [], scanned: 0, total: 0 };
      const vault = { address: deployment.escrowVault, abi: escrowVaultAbi } as const;
      const total = Number(await client.readContract({ ...vault, functionName: "nextEscrowId" }));
      const first = Math.max(1, total - MAX_SCAN + 1);
      const ids: bigint[] = [];
      for (let i = total; i >= first; i--) ids.push(BigInt(i));

      const me = account.toLowerCase();
      const items: MyEscrowRef[] = [];
      for (let k = 0; k < ids.length; k += BATCH) {
        const slice = ids.slice(k, k + BATCH);
        const rows = await Promise.all(
          slice.map((id) => client.readContract({ ...vault, functionName: "getEscrow", args: [id] })),
        );
        rows.forEach((e, j) => {
          const role =
            e.buyer.toLowerCase() === me
              ? "buyer"
              : e.seller.toLowerCase() === me
                ? "seller"
                : e.arbiter.toLowerCase() === me
                  ? "arbiter"
                  : undefined;
          if (role) items.push({ id: slice[j], role });
        });
      }
      return { items, scanned: ids.length, total };
    },
  });
}
