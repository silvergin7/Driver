import { describe, expect, it } from "vitest";
import { formatDvr } from "./format-dvr";

describe("formatDvr", () => {
  it("formats zero", () => {
    expect(formatDvr(0n)).toBe("0");
  });

  it("formats a whole token amount with grouping", () => {
    expect(formatDvr(950_000n * 10n ** 18n)).toBe("950,000");
  });

  it("formats a fractional token amount", () => {
    expect(formatDvr(12_500_000_000_000_000_000n)).toBe("12.5");
  });

  it("formats a single wei", () => {
    expect(formatDvr(1n)).toBe("0.000000000000000001");
  });
});
