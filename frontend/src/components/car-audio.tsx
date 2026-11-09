"use client";

import { createContext, useContext, useRef, type ReactNode } from "react";
import { carCues, cueAllowed, type CueName } from "@/lib/car-cues";
import { motionAllowed } from "@/lib/motion";
import { soundEnabledFromStorage, soundStorageKey } from "@/lib/sound-preference";

const CarAudioContext = createContext<(cue: CueName) => void>(() => {});

export function useCarAudio(): (cue: CueName) => void {
  return useContext(CarAudioContext);
}

export function CarAudioProvider({ children }: { children: ReactNode }) {
  const audio = useRef<AudioContext | null>(null);
  const stopDrive = useRef<(() => void) | null>(null);

  function play(cue: CueName) {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const enabled = soundEnabledFromStorage(() => localStorage.getItem(soundStorageKey));
    if (!cueAllowed({ enabled, reducedMotion: !motionAllowed(reduced) })) {
      return;
    }
    const ctx = audioContext();
    if (cue === "rev") {
      playRev(ctx);
      return;
    }
    if (cue === "drive") {
      playDrive(ctx);
      return;
    }
    if (cue === "chime") {
      playChime(ctx);
      return;
    }
    playOn(ctx);
  }

  function audioContext(): AudioContext {
    if (audio.current === null) {
      audio.current = new AudioContext();
    }
    if (audio.current.state === "suspended") {
      void audio.current.resume();
    }
    return audio.current;
  }

  function playRev(ctx: AudioContext) {
    const cue = carCues.rev;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = cue.type;
    const start = ctx.currentTime;
    const [first, ...rest] = cue.steps;
    if (first === undefined) {
      return;
    }
    osc.frequency.setValueAtTime(first.frequencyHz, start + first.atMs / 1000);
    for (const step of rest) {
      osc.frequency.linearRampToValueAtTime(step.frequencyHz, start + step.atMs / 1000);
    }
    envelope(gain, start, cue.durationMs / 1000, cue.peakGain);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(start);
    osc.stop(start + cue.durationMs / 1000);
  }

  function playDrive(ctx: AudioContext) {
    stopDrive.current?.();
    const cue = carCues.drive;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = cue.type;
    const start = ctx.currentTime;
    const end = start + cue.durationMs / 1000;
    osc.frequency.setValueAtTime(cue.frequencyHz, start);
    envelope(gain, start, cue.durationMs / 1000, cue.peakGain);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(start);
    osc.stop(end);
    let stopped = false;
    stopDrive.current = () => {
      if (stopped) {
        return;
      }
      stopped = true;
      stopOscillator(osc);
      stopDrive.current = null;
    };
  }

  function playChime(ctx: AudioContext) {
    const cue = carCues.chime;
    const start = ctx.currentTime;
    for (const note of cue.notes) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      const noteStart = start + note.atMs / 1000;
      const noteEnd = noteStart + note.lengthMs / 1000;
      osc.type = "sine";
      osc.frequency.setValueAtTime(note.frequencyHz, noteStart);
      envelope(gain, noteStart, note.lengthMs / 1000, cue.peakGain);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(noteStart);
      osc.stop(noteEnd);
    }
  }

  function playOn(ctx: AudioContext) {
    const cue = carCues.on;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    const start = ctx.currentTime;
    osc.type = cue.type;
    osc.frequency.setValueAtTime(cue.frequencyHz, start);
    envelope(gain, start, cue.durationMs / 1000, cue.peakGain);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(start);
    osc.stop(start + cue.durationMs / 1000);
  }

  return <CarAudioContext.Provider value={play}>{children}</CarAudioContext.Provider>;
}

function envelope(gain: GainNode, start: number, durationSec: number, peak: number) {
  const attack = Math.min(0.02, durationSec / 2);
  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(peak, start + attack);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + durationSec);
}

function stopOscillator(osc: OscillatorNode) {
  try {
    osc.stop();
  } catch (error) {
    if (!(error instanceof DOMException)) {
      throw error;
    }
  }
}
