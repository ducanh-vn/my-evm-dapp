"use client";

import { BalancesPanel } from "@/components/BalancesPanel";
import { CreateEscrowForm } from "@/components/CreateEscrowForm";
import { MyEscrows } from "@/components/MyEscrows";
import { TimeTravelPanel } from "@/components/TimeTravelPanel";

export default function HomePage() {
  return (
    <div className="grid">
      <div className="col">
        <CreateEscrowForm />
      </div>
      <div className="col">
        <MyEscrows />
        <BalancesPanel />
        <TimeTravelPanel />
      </div>
    </div>
  );
}
