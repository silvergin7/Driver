import { describe, expect, it } from "vitest";
import { minAmountAfterSlippage } from "./slippage";

describe("minAmountAfterSlippage", () => {
  it("floors one percent off the quoted amount", () => {
    expect(minAmountAfterSlippage(1_000n)).toBe(990n);
  });

  it("floors a one-base-unit quote to zero", () => {
    expect(minAmountAfterSlippage(1n)).toBe(0n);
  });
});
