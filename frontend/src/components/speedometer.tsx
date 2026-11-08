"use client";

import { useEffect, useRef } from "react";
import { useMotionAllowed } from "@/components/use-motion";
import { formatBps } from "@/lib/format-bps";
import { gaugeAngle, needleMotion } from "@/lib/gauge";

export function Speedometer({
  caption,
  max,
  value,
}: {
  caption: string;
  max: bigint;
  value: bigint;
}) {
  const motion = useMotionAllowed();
  const target = gaugeAngle(value, max);
  const needle = useRef<SVGLineElement>(null);
  const seen = useRef(false);

  useEffect(() => {
    const node = needle.current;
    if (node === null) {
      return;
    }
    for (const animation of node.getAnimations()) {
      animation.cancel();
    }
    if (!motion) {
      node.style.transform = `rotate(${target}deg)`;
      return;
    }
    const kind = needleMotion({ seen: seen.current, reducedMotion: false });
    seen.current = true;
    if (kind === "jump") {
      node.style.transform = `rotate(${target}deg)`;
      return;
    }
    node.animate(
      [{ transform: "rotate(-120deg)" }, { transform: `rotate(${target}deg)` }],
      { duration: 600, easing: "ease-out", fill: "forwards" },
    );
  }, [motion, target]);

  return (
    <figure className="flex flex-col items-center gap-1">
      <figcaption className="text-sm text-ink-muted">{caption}</figcaption>
      <svg viewBox="0 0 112 100" className="h-auto w-28" aria-hidden="true">
        <path
          d="M24.82 88 A36 36 0 1 1 87.18 88"
          fill="none"
          strokeWidth="8"
          strokeLinecap="round"
          className="stroke-line"
        />
        <line
          ref={needle}
          x1="56"
          y1="70"
          x2="56"
          y2="34"
          strokeWidth="3"
          strokeLinecap="round"
          className="stroke-brand"
          style={{ transform: `rotate(${target}deg)`, transformOrigin: "56px 70px" }}
        />
        <circle cx="56" cy="70" r="4" className="fill-brand" />
      </svg>
      <p className="text-sm text-ink tabular-nums">{`${formatBps(value)} APR`}</p>
    </figure>
  );
}
