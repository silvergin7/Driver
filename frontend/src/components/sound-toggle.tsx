"use client";

import { useSyncExternalStore } from "react";
import { useCarAudio } from "@/components/car-audio";
import {
  persistSoundEnabled,
  soundEnabledFromStorage,
  soundStorageKey,
} from "@/lib/sound-preference";

const soundChange = "driver-sound-change";

function subscribe(onStoreChange: () => void) {
  window.addEventListener("storage", onStoreChange);
  window.addEventListener(soundChange, onStoreChange);
  return () => {
    window.removeEventListener("storage", onStoreChange);
    window.removeEventListener(soundChange, onStoreChange);
  };
}

function readEnabled(): boolean {
  return soundEnabledFromStorage(() => localStorage.getItem(soundStorageKey));
}

export function SoundToggle({ labelled = false }: { labelled?: boolean }) {
  const enabled = useSyncExternalStore(subscribe, readEnabled, () => false);
  const play = useCarAudio();
  const label = enabled ? "Turn car sounds off" : "Turn car sounds on";

  function toggle() {
    const next = !enabled;
    const saved = persistSoundEnabled(next, (value) => {
      localStorage.setItem(soundStorageKey, value);
    });
    if (!saved) {
      return;
    }
    window.dispatchEvent(new Event(soundChange));
    if (next) {
      play("on");
    }
  }

  return (
    <button
      type="button"
      className={
        labelled
          ? "inline-flex min-h-11 items-center text-ink"
          : "inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-ink hover:bg-surface"
      }
      aria-pressed={enabled}
      aria-label={label}
      onClick={toggle}
    >
      {labelled ? "Car sounds" : <SpeakerIcon muted={!enabled} />}
    </button>
  );
}

function SpeakerIcon({ muted }: { muted: boolean }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-6 w-6">
      <path d="M4 9h4l5-4v14l-5-4H4Z" fill="currentColor" />
      {muted ? (
        <path
          d="M16 9l5 6M21 9l-5 6"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        />
      ) : (
        <path
          d="M16 9a4 4 0 0 1 0 6M18.5 6.5a7 7 0 0 1 0 11"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        />
      )}
    </svg>
  );
}
