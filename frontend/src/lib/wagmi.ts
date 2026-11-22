import { createConfig, http, injected } from "wagmi";
import { baseSepolia, foundry } from "wagmi/chains";

/** RPC của Anvil local. Có thể đổi bằng NEXT_PUBLIC_LOCAL_RPC_URL. */
export const LOCAL_RPC_URL = process.env.NEXT_PUBLIC_LOCAL_RPC_URL ?? "http://127.0.0.1:8545";

/**
 * RPC Base Sepolia cho trình duyệt. Mặc định dùng RPC công khai của Base.
 * Lưu ý: biến NEXT_PUBLIC_* bị lộ ra trình duyệt, KHÔNG dùng URL có API key bí mật.
 */
const BASE_SEPOLIA_RPC_URL = process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL || undefined;

export const SUPPORTED_CHAINS = [baseSepolia, foundry] as const;

export const wagmiConfig = createConfig({
  chains: SUPPORTED_CHAINS,
  connectors: [injected()],
  transports: {
    [baseSepolia.id]: http(BASE_SEPOLIA_RPC_URL),
    [foundry.id]: http(LOCAL_RPC_URL),
  },
  ssr: true,
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
