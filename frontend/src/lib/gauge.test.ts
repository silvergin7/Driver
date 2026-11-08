import { describe, expect, it } from "vitest";
import { gaugeAngle, needleMotion } from "./gauge";

describe("gaugeAngle", () => {
  it("rests at the start, reaches the cap, and clamps", () => {
    expect(gaugeAngle(0n, 500n)).toBe(-120);
    expect(gaugeAngle(250n, 500n)).toBe(0);
    expect(gaugeAngle(500n, 500n)).toBe(120);
    expect(gaugeAngle(600n, 500n)).toBe(120);
  });
});

describe("needleMotion", () => {
  it("sweeps once, then jumps when the value changes", () => {
    expect(needleMotion({ seen: false, reducedMotion: false })).toBe("sweep");
    expect(needleMotion({ seen: true, reducedMotion: false })).toBe("jump");
    expect(needleMotion({ seen: false, reducedMotion: true })).toBe("jump");
  });
});
