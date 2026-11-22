"use client";

import { useReadContracts } from "wagmi";

import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

/** Tham số hiện hành của vault: phí, trọng tài mặc định, trạng thái pause. */
export function useVaultParams() {
  const { deployment } = useVaultDeployment();
  const vault = { address: deployment?.escrowVault, abi: escrowVaultAbi } as const;
  const { data, refetch } = useReadContracts({
    contracts: [
      { ...vault, functionName: "feeBps" },
      { ...vault, functionName: "defaultArbiter" },
      { ...vault, functionName: "paused" },
      { ...vault, functionName: "isTokenAllowed", args: [deployment?.usdc ?? "0x0000000000000000000000000000000000000000"] },
    ],
    query: { enabled: !!deployment, refetchInterval: 10_000 },
  });
  return {
    feeBps: data?.[0]?.result !== undefined ? Number(data[0].result) : undefined,
    defaultArbiter: data?.[1]?.result,
    paused: data?.[2]?.result,
    usdcAllowed: data?.[3]?.result,
    refetch,
  };
}
