import { describe, expect, it } from "vitest";
import { ringFraction, ringPresentation } from "./ring";

describe("ringFraction", () => {
  it("uses the cooldown that was read", () => {
    const period = 1_000n;
    expect(ringFraction(0n, period)).toBe(1);
    expect(ringFraction(period, period)).toBe(0);
    expect(ringFraction(500n, period)).toBe(0.5);
    expect(ringFraction(250n, period)).toBe(0.75);
  });

  it("does not invent a day when the period is zero", () => {
    expect(ringFraction(0n, 0n)).toBe(0);
  });
});

describe("ringPresentation", () => {
  it("empties and greys the ring while the daily cap is full", () => {
    expect(
      ringPresentation({ dailyCap: true, remaining: 0n, period: 1_000n }),
    ).toEqual({ fraction: 0, grey: true });
  });

  it("shows the cooldown when the cap is open", () => {
    expect(
      ringPresentation({ dailyCap: false, remaining: 0n, period: 1_000n }),
    ).toEqual({ fraction: 1, grey: false });
  });
});
