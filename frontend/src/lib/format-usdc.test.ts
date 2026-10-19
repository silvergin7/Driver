import { describe, expect, it } from "vitest";
import { formatUsdc } from "./format-usdc";

describe("formatUsdc", () => {
  it("formats zero", () => {
    expect(formatUsdc(0n)).toBe("0");
  });

  it("formats a whole token amount with grouping", () => {
    expect(formatUsdc(15_000n * 10n ** 6n)).toBe("15,000");
  });

  it("formats a fractional token amount", () => {
    expect(formatUsdc(100_500_000n)).toBe("100.5");
  });

  it("formats a single base unit", () => {
    expect(formatUsdc(1n)).toBe("0.000001");
  });
});
