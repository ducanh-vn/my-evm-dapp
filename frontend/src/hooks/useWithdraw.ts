"use client";

import type { Address } from "viem";

import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useTxAction } from "@/hooks/useTxAction";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

/** Rút số dư chờ rút: về ví mình (`withdraw`) hoặc sang ví khác (`withdrawTo`). */
export function useWithdraw() {
  const { deployment } = useVaultDeployment();
  const tx = useTxAction();

  async function withdraw(token: Address, to?: Address) {
    if (!deployment) return;
    const vault = { address: deployment.escrowVault, abi: escrowVaultAbi } as const;
    if (to) {
      await tx.writeContractAsync({ ...vault, functionName: "withdrawTo", args: [token, to] });
    } else {
      await tx.writeContractAsync({ ...vault, functionName: "withdraw", args: [token] });
    }
  }

  return { withdraw, tx };
}
