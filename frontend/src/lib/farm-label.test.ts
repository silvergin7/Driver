import { describe, expect, it } from "vitest";
import { farmLabel } from "./farm-label";

const unknown = "0x0000000000000000000000000000000000000001";

describe("farmLabel", () => {
  it("names the four listed rates", () => {
    expect(farmLabel(500n, unknown)).toBe("Cruise");
    expect(farmLabel(4_000n, unknown)).toBe("Highway");
    expect(farmLabel(8_000n, unknown)).toBe("Autobahn");
    expect(farmLabel(16_000n, unknown)).toBe("Drift");
  });

  it("shows the address for an unknown rate", () => {
    expect(farmLabel(1n, unknown)).toBe(unknown);
  });
});