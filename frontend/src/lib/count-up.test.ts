import { describe, expect, it } from "vitest";
import { countUpFrames, countUpPlan } from "./count-up";

describe("countUpFrames", () => {
  it("ends on the exact formatted text", () => {
    for (const final of ["1,234.5 mUSDC", "0 DVR"]) {
      const frames = countUpFrames(final, 8);
      expect(frames).toHaveLength(8);
      expect(frames[7]).toBe(final);
    }
  });

  it("formats the frames for 1,234.5 mUSDC with commas and one decimal", () => {
    const frames = countUpFrames("1,234.5 mUSDC", 8);
    expect(frames[0]).toBe("154.3 mUSDC");
    expect(frames[3]).toBe("617.2 mUSDC");
    expect(frames[6]).toBe("1,080.1 mUSDC");
    for (const frame of frames) {
      const number = frame.slice(0, frame.indexOf(" "));
      expect(number).toMatch(/^(\d{1,3})(,\d{3})*(\.\d)$/);
      expect(number.split(".")[1]).toHaveLength(1);
      expect(number).not.toMatch(/[eE]|000000/);
    }
  });
});

describe("countUpPlan", () => {
  it("animates the first time a value appears", () => {
    const plan = countUpPlan({
      previous: undefined,
      next: "15,000 mUSDC",
      reducedMotion: false,
    });
    expect(plan.animate).toBe(true);
    expect(plan.frames).toHaveLength(8);
    expect(plan.frames[7]).toBe("15,000 mUSDC");
  });

  it("does not replay when the value changes", () => {
    const plan = countUpPlan({
      previous: "15,000 mUSDC",
      next: "15,001 mUSDC",
      reducedMotion: false,
    });
    expect(plan.animate).toBe(false);
    expect(plan.frames).toEqual(["15,001 mUSDC"]);
  });

  it("shows the final text at once under reduced motion", () => {
    const plan = countUpPlan({
      previous: undefined,
      next: "15,000 mUSDC",
      reducedMotion: true,
    });
    expect(plan.animate).toBe(false);
    expect(plan.frames).toEqual(["15,000 mUSDC"]);
  });
});
