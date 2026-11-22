"use client";

import { erc20Abi, parseEventLogs, type Address } from "viem";
import { useAccount, useReadContract } from "wagmi";

import { NATIVE_TOKEN } from "@/constants/addresses";
import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useTxAction } from "@/hooks/useTxAction";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

export type CreateEscrowInput = {
  seller: Address;
  token: Address;
  amount: bigint;
  deliveryDays: number;
  arbiter: Address;
  maxFeeBps: number;
};

/**
 * Tạo escrow. Với ERC-20 cần `approve` trước: hook tách 2 giao dịch (approve, create),
 * mỗi giao dịch có trạng thái chờ ký ví / chờ block riêng.
 */
export function useCreateEscrow(token: Address, amount: bigint) {
  const { address: account } = useAccount();
  const { deployment } = useVaultDeployment();
  const approveTx = useTxAction();
  const createTx = useTxAction();

  const isNative = token === NATIVE_TOKEN;
  const allowance = useReadContract({
    address: isNative ? undefined : token,
    abi: erc20Abi,
    functionName: "allowance",
    args: account && deployment ? [account, deployment.escrowVault] : undefined,
    query: { enabled: !isNative && !!account && !!deployment, refetchInterval: 4_000 },
  });
  const needsApproval = !isNative && amount > 0n && (allowance.data ?? 0n) < amount;

  async function approve() {
    if (!deployment) return;
    await approveTx.writeContractAsync({
      address: token,
      abi: erc20Abi,
      functionName: "approve",
      args: [deployment.escrowVault, amount],
    });
  }

  async function create(input: CreateEscrowInput) {
    if (!deployment) return;
    await createTx.writeContractAsync({
      address: deployment.escrowVault,
      abi: escrowVaultAbi,
      functionName: "createEscrow",
      args: [
        input.seller,
        input.token,
        input.amount,
        input.deliveryDays * 86_400,
        input.arbiter,
        input.maxFeeBps,
      ],
      value: input.token === NATIVE_TOKEN ? input.amount : 0n,
    });
  }

  const createdId = createTx.receipt
    ? parseEventLogs({ abi: escrowVaultAbi, eventName: "EscrowCreated", logs: createTx.receipt.logs })[0]?.args.id
    : undefined;

  return { needsApproval, approve, approveTx, create, createTx, createdId, refetchAllowance: allowance.refetch };
}
