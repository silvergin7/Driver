import { describe, expect, it } from "vitest";
import { farmAprBps } from "./farm-apr";
import { formatBps } from "./format-bps";

const live = {
  aprBps: 500n,
  active: true,
  paused: false,
  rewardReserve: 1n,
};

describe("farmAprBps", () => {
  it("returns the farm rate when the farm is live", () => {
    const rate = farmAprBps(live);
    expect(rate).toBe(500n);
    expect(formatBps(rate)).toBe("5%");
  });

  it("returns zero when the farm is paused", () => {
    expect(farmAprBps({ ...live, paused: true })).toBe(0n);
  });

  it("returns zero when the reward reserve is empty", () => {
    expect(farmAprBps({ ...live, rewardReserve: 0n })).toBe(0n);
  });

  it("returns zero when there is no active farm", () => {
    expect(farmAprBps({ ...live, active: false })).toBe(0n);
  });
});
