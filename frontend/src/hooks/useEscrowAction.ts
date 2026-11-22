"use client";

import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useTxAction } from "@/hooks/useTxAction";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";
import type { EscrowAction } from "@/types/escrow";

/** Gọi một thao tác của escrow (markDelivered, release, refund, raiseDispute, resolveDispute, claimTimeoutRefund). */
export function useEscrowAction() {
  const { deployment } = useVaultDeployment();
  const tx = useTxAction();

  async function run(action: EscrowAction, id: bigint, buyerBps = 0) {
    if (!deployment) return;
    const vault = { address: deployment.escrowVault, abi: escrowVaultAbi } as const;
    if (action === "resolveDispute") {
      await tx.writeContractAsync({ ...vault, functionName: "resolveDispute", args: [id, buyerBps] });
    } else {
      await tx.writeContractAsync({ ...vault, functionName: action, args: [id] });
    }
  }

  return { run, tx };
}
