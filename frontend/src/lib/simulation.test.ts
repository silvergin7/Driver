import { describe, expect, it } from "vitest";
import {
  findRun,
  lockChoices,
  priceUsdcPerDvr,
  simulation,
  stepCopy,
  stepIndexAfter,
  stepRows,
  swapChoices,
  voteChoices,
} from "./simulation";

describe("simulation runs", () => {
  it("records every combination", () => {
    const ids = simulation.runs.map(
      (run) => `${run.swapUsdc}-${run.lock}-${run.vote}`,
    );
    expect(new Set(ids).size).toBe(18);
    for (const swap of swapChoices) {
      for (const lock of lockChoices) {
        for (const vote of voteChoices) {
          const run = findRun(swap.id, lock.id, vote.id);
          expect(run.steps.map((step) => step.id)).toEqual(
            stepCopy.map((step) => step.id),
          );
        }
      }
    }
  });

  it("prices the fresh pool at 0.02 mUSDC per DVR", () => {
    const start = findRun("25", "half", "highway").steps[0];
    expect(start).toBeDefined();
    if (start === undefined) {
      return;
    }
    expect(priceUsdcPerDvr(BigInt(start.poolDvr), BigInt(start.poolUsdc))).toBe(
      "0.02",
    );
  });

  it("shows a buyback and a later top-up for Drift", () => {
    const run = findRun("100", "all", "drift");
    const first = run.steps.find((step) => step.id === "harvest-fund-2");
    const second = run.steps.find((step) => step.id === "harvest-fund-2-again");
    expect(first?.rebalanceAmount).toBe("0");
    expect(BigInt(second?.rebalanceAmount ?? "0")).toBeGreaterThan(0n);
    expect(BigInt(second?.totalSupply ?? "0")).toBeLessThan(
      BigInt(run.steps[0]?.totalSupply ?? "0"),
    );
    const rows = stepRows(run.steps, run.steps.length - 1);
    expect(rows.find((row) => row.label === "Moved to Cruise Control")?.value).toContain(
      "→",
    );
  });
});

describe("stepIndexAfter", () => {
  it("walks back, forward, and back to the start", () => {
    expect(stepIndexAfter(0, 11, "back")).toBe(0);
    expect(stepIndexAfter(0, 11, "next")).toBe(1);
    expect(stepIndexAfter(10, 11, "next")).toBe(10);
    expect(stepIndexAfter(4, 11, "back")).toBe(3);
    expect(stepIndexAfter(4, 11, "start")).toBe(0);
  });
});
