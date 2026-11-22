"use client";

import { useQuery } from "@tanstack/react-query";
import { getAbiItem, type Address } from "viem";
import { usePublicClient } from "wagmi";

import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

const CREATED_EVENT = getAbiItem({ abi: escrowVaultAbi, name: "EscrowCreated" });
/** Nhiều RPC công khai giới hạn khoảng block mỗi lần gọi eth_getLogs. */
const LOG_CHUNK = 9_000n;

export type MyEscrowRef = { id: bigint; role: "buyer" | "seller" | "arbiter"; blockNumber: bigint };

/**
 * Danh sách escrow liên quan tới `account` bằng cách đọc event EscrowCreated từ block deploy.
 * Đủ dùng cho MVP/local; khi lượng dữ liệu lớn sẽ chuyển sang Indexer (Ponder / The Graph).
 */
export function useMyEscrows(account?: Address) {
  const { deployment, chainId } = useVaultDeployment();
  const client = usePublicClient();

  return useQuery({
    queryKey: ["myEscrows", chainId, deployment?.escrowVault, account],
    enabled: !!client && !!deployment && !!account,
    refetchInterval: 8_000,
    queryFn: async (): Promise<MyEscrowRef[]> => {
      if (!client || !deployment || !account) return [];
      const latest = await client.getBlockNumber();
      const me = account.toLowerCase();
      const found: MyEscrowRef[] = [];
      for (let from = deployment.deployBlock; from <= latest; from += LOG_CHUNK) {
        const to = from + LOG_CHUNK - 1n > latest ? latest : from + LOG_CHUNK - 1n;
        const logs = await client.getLogs({
          address: deployment.escrowVault,
          event: CREATED_EVENT,
          fromBlock: from,
          toBlock: to,
        });
        for (const log of logs) {
          const { id, buyer, seller, arbiter } = log.args;
          if (id === undefined) continue;
          const role =
            buyer?.toLowerCase() === me
              ? "buyer"
              : seller?.toLowerCase() === me
                ? "seller"
                : arbiter?.toLowerCase() === me
                  ? "arbiter"
                  : undefined;
          if (role) found.push({ id, role, blockNumber: log.blockNumber ?? 0n });
        }
      }
      return found.sort((a, b) => (a.id < b.id ? 1 : -1));
    },
  });
}
