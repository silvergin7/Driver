import { describe, expect, it } from "vitest";
import { carCues, cueAllowed } from "./car-cues";
import { driveMs } from "./motion";

describe("carCues", () => {
  it("locks the rev", () => {
    expect(carCues.rev).toEqual({
      durationMs: 350,
      peakGain: 0.08,
      type: "sawtooth",
      steps: [
        { atMs: 0, frequencyHz: 90 },
        { atMs: 140, frequencyHz: 180 },
        { atMs: 350, frequencyHz: 110 },
      ],
    });
  });

  it("locks the drive to the same duration as the car", () => {
    expect(carCues.drive).toEqual({
      durationMs: 600,
      peakGain: 0.05,
      type: "sawtooth",
      frequencyHz: 70,
    });
    expect(carCues.drive.durationMs).toBe(driveMs);
  });

  it("locks the chime", () => {
    expect(carCues.chime).toEqual({
      peakGain: 0.06,
      notes: [
        { atMs: 0, frequencyHz: 523, lengthMs: 80 },
        { atMs: 100, frequencyHz: 659, lengthMs: 80 },
      ],
    });
  });

  it("locks the on blip", () => {
    expect(carCues.on).toEqual({
      durationMs: 40,
      peakGain: 0.04,
      frequencyHz: 880,
      type: "sine",
    });
  });
});

describe("cueAllowed", () => {
  it("plays only when sound is on and motion is allowed", () => {
    expect(cueAllowed({ enabled: true, reducedMotion: false })).toBe(true);
    expect(cueAllowed({ enabled: false, reducedMotion: false })).toBe(false);
    expect(cueAllowed({ enabled: true, reducedMotion: true })).toBe(false);
    expect(cueAllowed({ enabled: false, reducedMotion: true })).toBe(false);
  });
});
