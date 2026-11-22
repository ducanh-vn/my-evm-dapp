"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createTestClient, http } from "viem";
import { foundry } from "viem/chains";

import { LOCAL_RPC_URL } from "@/lib/wagmi";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

const testClient = createTestClient({ chain: foundry, mode: "anvil", transport: http(LOCAL_RPC_URL) });

/**
 * Tua thời gian chain (CHỈ trên Anvil local): tăng timestamp rồi đào 1 block.
 * Dùng để thử hạn giao hàng, 3 ngày khiếu nại, 14 ngày trọng tài mà không phải chờ thật.
 */
export function useTimeTravel() {
  const { isLocal } = useVaultDeployment();
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: async (seconds: number) => {
      if (!isLocal) throw new Error("Chỉ tua được thời gian trên Anvil local.");
      await testClient.increaseTime({ seconds });
      await testClient.mine({ blocks: 1 });
    },
    onSuccess: () => queryClient.invalidateQueries(),
  });
  return { isLocal, travel: mutation.mutate, isTraveling: mutation.isPending, error: mutation.error };
}
