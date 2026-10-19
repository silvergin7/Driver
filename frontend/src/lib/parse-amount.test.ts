import { describe, expect, it } from "vitest";
import { parseTokenAmount } from "./parse-amount";

describe("parseTokenAmount", () => {
  it("treats a blank field as empty", () => {
    expect(parseTokenAmount("  ", 18).status).toBe("empty");
  });

  it("rejects too many decimal places", () => {
    expect(parseTokenAmount("1.0000001", 6).status).toBe("invalid");
  });

  it("rejects a zero amount", () => {
    expect(parseTokenAmount("0.0", 18).status).toBe("zero");
  });

  it("parses a whole DVR amount", () => {
    expect(parseTokenAmount("10", 18)).toEqual({
      status: "amount",
      amount: 10n * 10n ** 18n,
    });
  });

  it("parses a fractional mUSDC amount", () => {
    expect(parseTokenAmount("100.5", 6)).toEqual({
      status: "amount",
      amount: 100_500_000n,
    });
  });
});
