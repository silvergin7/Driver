import { describe, expect, it } from "vitest";
import { parseTokenAmount } from "./parse-amount";
import { maxAmountText } from "./max-amount";

describe("maxAmountText", () => {
  it("round-trips one base unit of mUSDC", () => {
    const text = maxAmountText(1n, 6);
    expect(text.includes(",")).toBe(false);
    expect(parseTokenAmount(text, 6)).toEqual({ status: "amount", amount: 1n });
  });

  it("round-trips a whole balance", () => {
    const text = maxAmountText(10_000000n, 6);
    expect(text.includes(",")).toBe(false);
    expect(parseTokenAmount(text, 6)).toEqual({ status: "amount", amount: 10_000000n });
  });

  it("round-trips a balance large enough to tempt a thousands separator", () => {
    const text = maxAmountText(1_000_000000n, 6);
    expect(text.includes(",")).toBe(false);
    expect(parseTokenAmount(text, 6)).toEqual({ status: "amount", amount: 1_000_000000n });
  });

  it("round-trips a fractional DVR balance", () => {
    const amount = 12_500_000_000_000_000_000n;
    const text = maxAmountText(amount, 18);
    expect(parseTokenAmount(text, 18)).toEqual({ status: "amount", amount });
  });
});
