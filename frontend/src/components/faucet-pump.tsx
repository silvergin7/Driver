"use client";

import { useEffect, useRef } from "react";
import { Pump, readoutClass } from "@/components/pump-frame";
import { TokenIcon } from "@/components/token-icon";
import { TransactionLink } from "@/components/transaction-link";
import { useMotionAllowed } from "@/components/use-motion";

const radius = 28;
const circumference = 2 * Math.PI * radius;
const coneAngles = [0, 45, 90, 135, 180, 225, 270, 315];

export function FaucetPump({
  title,
  bandClass,
  amount,
  unit,
  fraction,
  grey,
  countdown,
  buttonLabel,
  canClaim,
  onClaim,
  status,
  hash,
  reason,
  error,
  celebrate,
}: {
  title: string;
  bandClass: string;
  amount: string | undefined;
  unit: string;
  fraction: number | undefined;
  grey: boolean;
  countdown: string | undefined;
  buttonLabel: string;
  canClaim: boolean;
  onClaim: () => void;
  status: string | undefined;
  hash: `0x${string}` | undefined;
  reason: string | undefined;
  error: string | undefined;
  celebrate: boolean;
}) {
  const motion = useMotionAllowed();

  return (
    <Pump
      title={
        <span className="inline-flex items-center gap-2">
          <TokenIcon
            token={title === "DVR" ? "dvr" : "musdc"}
            className={title === "DVR" ? "h-6 w-9" : "h-6 w-6"}
          />
          {title}
        </span>
      }
      bandClass={bandClass}
    >
      <div className={`${readoutClass} relative overflow-hidden text-center`}>
        <p className="font-mono text-4xl tabular-nums sm:text-5xl">{amount ?? "…"}</p>
        <p className="text-sm text-slate-300">{unit}</p>
        {fraction !== undefined ? (
          <div className="mt-4 flex flex-col items-center gap-2">
            <svg
              viewBox="0 0 72 72"
              className={`h-[72px] w-[72px] -rotate-90 ${grey ? "opacity-40" : ""}`}
              aria-hidden="true"
            >
              <circle cx="36" cy="36" r={radius} fill="none" stroke="#334155" strokeWidth="6" />
              <circle
                cx="36"
                cy="36"
                r={radius}
                fill="none"
                stroke={grey ? "#64748b" : "#60a5fa"}
                strokeWidth="6"
                strokeDasharray={circumference}
                strokeDashoffset={circumference * (1 - fraction)}
                strokeLinecap="round"
              />
            </svg>
            {countdown !== undefined ? (
              <p className="text-sm text-slate-300 tabular-nums">{countdown}</p>
            ) : null}
          </div>
        ) : null}
        {celebrate && motion ? <ClaimBurst /> : null}
      </div>
      <button
        type="button"
        className="min-h-12 w-full rounded-md bg-brand px-3 py-2 text-lg text-on-brand disabled:border disabled:border-line disabled:bg-disabled-bg disabled:text-ink-muted"
        disabled={!canClaim}
        onClick={onClaim}
      >
        {buttonLabel}
      </button>
      {status ? <p className="text-sm text-ink-muted">{status}</p> : null}
      <TransactionLink hash={hash} />
      {reason ? <p className="text-sm text-ink-muted">{reason}</p> : null}
      {error ? <p role="alert">{error}</p> : null}
    </Pump>
  );
}

function ClaimBurst() {
  const refs = useRef<Array<HTMLSpanElement | null>>([]);

  useEffect(() => {
    const animations = coneAngles.map((degrees, index) => {
      const cone = refs.current[index];
      if (cone === undefined || cone === null) {
        return null;
      }
      const rad = (degrees * Math.PI) / 180;
      const x = Math.cos(rad) * 56;
      const y = Math.sin(rad) * 40;
      return cone.animate(
        [
          { transform: "translate(0px, 0px)", opacity: 1 },
          { transform: `translate(${x}px, ${y}px)`, opacity: 0 },
        ],
        { duration: 800, easing: "ease-out", fill: "forwards" },
      );
    });
    return () => {
      for (const animation of animations) {
        animation?.cancel();
      }
    };
  }, []);

  return (
    <div aria-hidden="true" className="pointer-events-none absolute inset-0">
      {coneAngles.map((degrees, index) => (
        <span
          key={degrees}
          ref={(node) => {
            refs.current[index] = node;
          }}
          className="absolute top-1/2 left-1/2 h-3 w-3"
        >
          <svg viewBox="0 0 12 12" className="h-3 w-3">
            <path d="M6 0 L12 12 H0 Z" fill="#e11d48" />
          </svg>
        </span>
      ))}
    </div>
  );
}
