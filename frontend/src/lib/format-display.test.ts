import { describe, expect, it } from "vitest";
import { formatDisplayAmount } from "./format-display";

describe("formatDisplayAmount", () => {
  it("rounds down to 4 decimals", () => {
    expect(formatDisplayAmount(1_234_590_000_000_000_000n, 18)).toBe("1.2345");
    expect(formatDisplayAmount(1_234_567n, 6)).toBe("1.2345");
  });

  it("trims trailing zeros", () => {
    expect(formatDisplayAmount(12_500_010_000_000_000_000n, 18)).toBe("12.5");
    expect(formatDisplayAmount(1_230_000n, 6)).toBe("1.23");
  });

  it("keeps commas", () => {
    expect(formatDisplayAmount(1_000_000_999_990_000_000_000_000n, 18)).toBe(
      "1,000,000.9999",
    );
  });

  it("keeps zero as 0", () => {
    expect(formatDisplayAmount(0n, 18)).toBe("0");
    expect(formatDisplayAmount(1n, 18)).toBe("0");
  });
});
