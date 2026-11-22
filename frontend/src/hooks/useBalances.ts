"use client";

import { erc20Abi, type Address } from "viem";
import { useBalance, useReadContracts } from "wagmi";

import { NATIVE_TOKEN } from "@/constants/addresses";
import { escrowVaultAbi } from "@/constants/escrowVaultAbi";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

/** Số dư ví (ETH, USDC) và số dư chờ rút trong vault (ETH, USDC) của `account`. */
export function useBalances(account?: Address) {
  const { deployment } = useVaultDeployment();
  const eth = useBalance({ address: account, query: { enabled: !!account, refetchInterval: 4_000 } });

  const vault = deployment?.escrowVault;
  const usdc = deployment?.usdc;
  const enabled = !!account && !!deployment;
  const { data, refetch } = useReadContracts({
    contracts: [
      { address: usdc, abi: erc20Abi, functionName: "balanceOf", args: account ? [account] : undefined },
      { address: vault, abi: escrowVaultAbi, functionName: "withdrawable", args: account ? [account, NATIVE_TOKEN] : undefined },
      { address: vault, abi: escrowVaultAbi, functionName: "withdrawable", args: account && usdc ? [account, usdc] : undefined },
    ],
    query: { enabled, refetchInterval: 4_000 },
  });

  return {
    walletEth: eth.data?.value,
    walletUsdc: data?.[0]?.result,
    pendingEth: data?.[1]?.result,
    pendingUsdc: data?.[2]?.result,
    refetch: () => {
      void eth.refetch();
      void refetch();
    },
  };
}
