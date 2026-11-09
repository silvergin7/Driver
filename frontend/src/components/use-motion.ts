"use client";

import { useSyncExternalStore } from "react";
import { motionAllowed } from "@/lib/motion";

function subscribe(onChange: () => void) {
  const media = window.matchMedia("(prefers-reduced-motion: reduce)");
  media.addEventListener("change", onChange);
  return () => media.removeEventListener("change", onChange);
}

export function useMotionAllowed(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => motionAllowed(window.matchMedia("(prefers-reduced-motion: reduce)").matches),
    () => false,
  );
}

export function useMotionPreference(): boolean | undefined {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia("(prefers-reduced-motion: reduce)").matches,
    () => undefined,
  );
}
