"use client";

import { erc20Abi, type Address } from "viem";
import { useReadContracts } from "wagmi";

import { NATIVE_TOKEN } from "@/constants/addresses";
import type { TokenInfo } from "@/types/escrow";

/** Symbol/decimals của token; `address(0)` là ETH. */
export function useTokenInfo(token?: Address): TokenInfo | undefined {
  const isNative = !token || token === NATIVE_TOKEN;
  const { data } = useReadContracts({
    contracts: [
      { address: token, abi: erc20Abi, functionName: "symbol" },
      { address: token, abi: erc20Abi, functionName: "decimals" },
    ],
    query: { enabled: !!token && !isNative, staleTime: Infinity },
  });

  if (isNative) return { address: NATIVE_TOKEN, symbol: "ETH", decimals: 18, isNative: true };
  const symbol = data?.[0]?.result;
  const decimals = data?.[1]?.result;
  if (symbol === undefined || decimals === undefined) return undefined;
  return { address: token, symbol, decimals: Number(decimals), isNative: false };
}
