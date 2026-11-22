"use client";

import { useVaultDeployment } from "@/hooks/useVaultDeployment";
import { useVaultParams } from "@/hooks/useVaultParams";

/** Cảnh báo khi chưa kết nối, sai mạng, chưa deploy trên mạng local, hoặc vault đang pause. */
export function NetworkNotice() {
  const { isConnected, isWrongNetwork, deployment, isLocal } = useVaultDeployment();
  const { paused } = useVaultParams();

  if (!isConnected) return <div className="notice">Hãy kết nối MetaMask để thao tác. Chưa kết nối vẫn xem được dữ liệu.</div>;
  if (isWrongNetwork)
    return <div className="notice warn">Ví đang ở mạng không được hỗ trợ. Hãy chuyển sang Base Sepolia hoặc Anvil local.</div>;
  if (!deployment && isLocal)
    return (
      <div className="notice warn">
        Chưa có contract trên Anvil local. Chạy Anvil và script <code>DeployLocalDemo</code> (xem
        docs/04-van-hanh/chay-local-anvil.md), rồi tải lại trang.
      </div>
    );
  if (paused) return <div className="notice warn">Vault đang tạm dừng: không tạo được escrow mới, các thao tác khác vẫn chạy.</div>;
  return null;
}
