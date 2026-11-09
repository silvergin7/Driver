import { driveMs, motionAllowed } from "./motion";

export const carCues = {
  rev: {
    durationMs: 350,
    peakGain: 0.08,
    type: "sawtooth",
    steps: [
      { atMs: 0, frequencyHz: 90 },
      { atMs: 140, frequencyHz: 180 },
      { atMs: 350, frequencyHz: 110 },
    ],
  },
  drive: {
    durationMs: driveMs,
    peakGain: 0.05,
    type: "sawtooth",
    frequencyHz: 70,
  },
  chime: {
    peakGain: 0.06,
    notes: [
      { atMs: 0, frequencyHz: 523, lengthMs: 80 },
      { atMs: 100, frequencyHz: 659, lengthMs: 80 },
    ],
  },
  on: {
    durationMs: 40,
    peakGain: 0.04,
    frequencyHz: 880,
    type: "sine",
  },
} as const;

export type CueName = keyof typeof carCues;

export function cueAllowed(input: { enabled: boolean; reducedMotion: boolean }): boolean {
  return input.enabled && motionAllowed(input.reducedMotion);
}
