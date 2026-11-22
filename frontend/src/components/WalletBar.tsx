"use client";

import Link from "next/link";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";

import { BASE_SEPOLIA_CHAIN_ID, LOCAL_CHAIN_ID } from "@/constants/addresses";
import { shortAddress } from "@/lib/format";
import { useVaultDeployment } from "@/hooks/useVaultDeployment";

const NETWORK_NAME: Record<number, string> = {
  [BASE_SEPOLIA_CHAIN_ID]: "Base Sepolia",
  [LOCAL_CHAIN_ID]: "Anvil local",
};

/** Thanh trên cùng: kết nối MetaMask, mạng hiện tại, nút chuyển mạng. */
export function WalletBar() {
  const { address, isConnected, chain } = useAccount();
  const { connect, connectors, isPending, error } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: isSwitching } = useSwitchChain();
  const { deployment, isWrongNetwork } = useVaultDeployment();
  // Dựa vào mạng thật của ví (không dùng giá trị dự phòng), để khi ví ở mạng lạ vẫn hiện đủ nút chuyển mạng.
  const walletChainId = chain?.id;

  return (
    <header className="wallet-bar">
      <Link href="/" className="brand">
        🔒 EscrowVault
      </Link>
      <div className="wallet-right">
        {isConnected && (
          <span className={`badge ${isWrongNetwork || !deployment ? "badge-warn" : ""}`}>
            {chain ? (NETWORK_NAME[chain.id] ?? chain.name) : "Mạng không hỗ trợ"}
          </span>
        )}
        {isConnected && walletChainId !== BASE_SEPOLIA_CHAIN_ID && (
          <button className="btn small" disabled={isSwitching} onClick={() => switchChain({ chainId: BASE_SEPOLIA_CHAIN_ID })}>
            → Base Sepolia
          </button>
        )}
        {isConnected && walletChainId !== LOCAL_CHAIN_ID && (
          <button className="btn small" disabled={isSwitching} onClick={() => switchChain({ chainId: LOCAL_CHAIN_ID })}>
            → Anvil
          </button>
        )}
        {isConnected ? (
          <>
            <code title={address}>{shortAddress(address)}</code>
            <button className="btn small" onClick={() => disconnect()}>
              Ngắt kết nối
            </button>
          </>
        ) : (
          <button
            className="btn primary"
            disabled={isPending || connectors.length === 0}
            onClick={() => connectors[0] && connect({ connector: connectors[0] })}
          >
            {isPending ? "Đang mở MetaMask…" : "Kết nối MetaMask"}
          </button>
        )}
      </div>
      {error && <p className="status error">⚠️ {error.message}</p>}
    </header>
  );
}
