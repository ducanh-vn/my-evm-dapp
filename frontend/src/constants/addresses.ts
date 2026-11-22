import type { Address } from "viem";
import { zeroAddress } from "viem";

import local from "./deployments/local.json";

/** Địa chỉ contract theo từng mạng. Không có private key hay RPC có API key ở đây. */
export type Deployment = {
  escrowVault: Address;
  usdc: Address;
  /** Block deploy: điểm bắt đầu khi đọc event (thay Indexer ở MVP). */
  deployBlock: bigint;
  explorerUrl?: string;
};

export const BASE_SEPOLIA_CHAIN_ID = 84_532;
export const LOCAL_CHAIN_ID = 31_337;

/** Base Sepolia: xem docs/02-ky-thuat/contract-addresses.md. */
const baseSepolia: Deployment = {
  escrowVault: "0xEC01EeE5BEeA3Ab571F7aE31E70f9f479618560e",
  usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
  deployBlock: 62_219_774n,
  explorerUrl: "https://sepolia.basescan.org",
};

/** Anvil local: file local.json do script/DeployLocalDemo.s.sol ghi ra sau mỗi lần deploy. */
const anvil: Deployment | undefined =
  local.escrowVault === zeroAddress
    ? undefined
    : {
        escrowVault: local.escrowVault as Address,
        usdc: local.usdc as Address,
        deployBlock: BigInt(local.deployBlock),
      };

export const DEPLOYMENTS: Record<number, Deployment | undefined> = {
  [BASE_SEPOLIA_CHAIN_ID]: baseSepolia,
  [LOCAL_CHAIN_ID]: anvil,
};

export const NATIVE_TOKEN: Address = zeroAddress;
