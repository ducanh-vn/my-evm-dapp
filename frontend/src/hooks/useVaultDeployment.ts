"use client";

import { useAccount, useChainId } from "wagmi";

import { DEPLOYMENTS, LOCAL_CHAIN_ID } from "@/constants/addresses";

/** Deployment ứng với mạng ví đang chọn (hoặc mạng mặc định khi chưa kết nối). */
export function useVaultDeployment() {
  const { chain, isConnected } = useAccount();
  const configChainId = useChainId();
  const chainId = chain?.id ?? configChainId;
  const deployment = DEPLOYMENTS[chainId];
  return {
    chainId,
    deployment,
    isConnected,
    isLocal: chainId === LOCAL_CHAIN_ID,
    /** Ví kết nối vào mạng không nằm trong danh sách hỗ trợ. */
    isWrongNetwork: isConnected && !chain,
  };
}
