import type { Metadata } from "next";
import type { ReactNode } from "react";

import { Providers } from "@/app/providers";
import { NetworkNotice } from "@/components/NetworkNotice";
import { WalletBar } from "@/components/WalletBar";

import "./globals.css";

export const metadata: Metadata = {
  title: "EscrowVault",
  description: "Ký quỹ thanh toán P2P trên Base",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="vi">
      <body>
        <Providers>
          <WalletBar />
          <main>
            <NetworkNotice />
            {children}
          </main>
        </Providers>
      </body>
    </html>
  );
}
