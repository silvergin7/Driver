"use client";

import { useEffect, useRef, useSyncExternalStore } from "react";
import { useCarAudio } from "@/components/car-audio";
import { toastCopy } from "@/lib/toast-copy";
import { dismissToast, publishToast, subscribeToast, toastSnapshot } from "@/lib/toast-store";

const toastMs = 5_000;

export function publishConfirmed(sentence: string): void {
  publishToast(toastCopy({ outcome: "confirmed", confirmed: sentence, error: "" }), true);
}

export function publishFailure(sentence: string): void {
  publishToast(toastCopy({ outcome: "failed", confirmed: "", error: sentence }), false);
}

export function useFailureToast(error: string | undefined): void {
  const shown = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (error === undefined) {
      shown.current = undefined;
      return;
    }
    if (shown.current === error) {
      return;
    }
    shown.current = error;
    publishFailure(error);
  }, [error]);
}

export function Toaster() {
  const toast = useSyncExternalStore(subscribeToast, toastSnapshot, () => undefined);
  const play = useCarAudio();
  const playRef = useRef(play);
  const played = useRef<number | undefined>(undefined);

  useEffect(() => {
    playRef.current = play;
  }, [play]);

  useEffect(() => {
    if (toast === undefined) {
      return;
    }
    const id = toast.id;
    if (toast.sound && played.current !== id) {
      played.current = id;
      playRef.current("chime");
    }
    const timer = window.setTimeout(() => dismissToast(id), toastMs);
    return () => window.clearTimeout(timer);
  }, [toast]);

  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed inset-x-4 bottom-4 z-50 flex justify-center"
    >
      {toast !== undefined ? (
        <div className="pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-xl border-2 border-sign bg-background p-4 text-ink shadow-raise">
          <svg viewBox="0 0 12 12" className="mt-1 h-4 w-4 shrink-0" aria-hidden="true">
            <path d="M6 0 L12 12 H0 Z" className="fill-brand" />
          </svg>
          <p className="flex-1">{toast.message}</p>
          <button
            type="button"
            className="min-h-11 min-w-11 text-ink"
            aria-label="Close"
            onClick={() => dismissToast(toast.id)}
          >
            ×
          </button>
        </div>
      ) : null}
    </div>
  );
}
