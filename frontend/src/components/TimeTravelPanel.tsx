"use client";

import { formatDateTime } from "@/lib/format";
import { useChainTime } from "@/hooks/useChainTime";
import { useTimeTravel } from "@/hooks/useTimeTravel";

const STEPS: { label: string; seconds: number }[] = [
  { label: "+1 giờ", seconds: 3_600 },
  { label: "+1 ngày", seconds: 86_400 },
  { label: "+3 ngày", seconds: 3 * 86_400 },
  { label: "+7 ngày", seconds: 7 * 86_400 },
  { label: "+14 ngày", seconds: 14 * 86_400 },
];

/** Tua thời gian chain — chỉ hiện trên Anvil local. */
export function TimeTravelPanel() {
  const { isLocal, travel, isTraveling, error } = useTimeTravel();
  const now = useChainTime();
  if (!isLocal) return null;

  return (
    <section className="card local-only">
      <h2>⏩ Tua thời gian (chỉ Anvil)</h2>
      <p className="muted">Giờ trên chain: {formatDateTime(now)}</p>
      <div className="row">
        {STEPS.map((s) => (
          <button key={s.seconds} className="btn small" disabled={isTraveling} onClick={() => travel(s.seconds)}>
            {s.label}
          </button>
        ))}
      </div>
      {error && <p className="status error">⚠️ {error.message}</p>}
    </section>
  );
}
