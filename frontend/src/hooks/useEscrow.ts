"use client";

import { useReadContract } from "wagmi";

import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";
import type { Escrow } from "@/types/escrow";

/** Đọc một escrow theo id; tự làm mới mỗi 4 giây. */
export function useEscrow(id?: bigint) {
  const { deployment } = useVaultDeployment();
  const query = useReadContract({
    address: deployment?.escrowVault,
    abi: escrowVaultAbi,
    functionName: "getEscrow",
    args: id !== undefined ? [id] : undefined,
    query: { enabled: !!deployment && id !== undefined && id > 0n, refetchInterval: 4_000 },
  });

  const raw = query.data;
  const escrow: Escrow | undefined = raw
    ? {
        buyer: raw.buyer,
        deliveryDeadline: Number(raw.deliveryDeadline),
        feeBps: Number(raw.feeBps),
        status: Number(raw.status),
        seller: raw.seller,
        disputeDeadline: Number(raw.disputeDeadline),
        arbiter: raw.arbiter,
        arbitrationDeadline: Number(raw.arbitrationDeadline),
        token: raw.token,
        amount: raw.amount,
      }
    : undefined;

  return { escrow, isLoading: query.isLoading, error: query.error, refetch: query.refetch };
}
