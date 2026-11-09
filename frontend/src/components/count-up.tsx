"use client";

import { useEffect, useRef, useState } from "react";
import { useMotionPreference } from "@/components/use-motion";
import { countUpPlan } from "@/lib/count-up";

const countMs = 800;
const countFrames = 8;

export function CountUp({ value, className }: { value: string; className?: string }) {
  const reduced = useMotionPreference();
  const previous = useRef<string | undefined>(undefined);
  const [mode, setMode] = useState<"pending" | "counting" | "settled">("pending");
  const [frame, setFrame] = useState(value);
  const [tracked, setTracked] = useState(value);

  if (tracked !== value) {
    setTracked(value);
    setFrame(value);
    if (mode !== "pending") {
      setMode("settled");
    }
  }

  useEffect(() => {
    if (reduced === undefined) {
      return;
    }
    const plan = countUpPlan({
      previous: previous.current,
      next: value,
      reducedMotion: reduced,
    });
    previous.current = value;
    if (!plan.animate) {
      const timer = window.setTimeout(() => setMode("settled"), 0);
      return () => window.clearTimeout(timer);
    }
    const timers = plan.frames.map((text, index) =>
      window.setTimeout(
        () => {
          setMode("counting");
          setFrame(text);
          if (index === countFrames - 1) {
            setMode("settled");
          }
        },
        Math.round((countMs * index) / (countFrames - 1)),
      ),
    );
    return () => {
      for (const timer of timers) {
        window.clearTimeout(timer);
      }
    };
  }, [reduced, value]);

  const visible = mode === "counting" ? frame : value;

  return (
    <span className={className}>
      <span className="sr-only">{value}</span>
      <span aria-hidden="true">{visible}</span>
    </span>
  );
}
