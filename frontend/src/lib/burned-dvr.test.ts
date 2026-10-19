import { describe, expect, it } from "vitest";
import { burnedDvr } from "./burned-dvr";

describe("burnedDvr", () => {
  it("subtracts the supply from the amount minted", () => {
    expect(burnedDvr(1_000n, 900n)).toBe(100n);
  });

  it("is zero when nothing has been burned", () => {
    expect(burnedDvr(1_000n, 1_000n)).toBe(0n);
  });

  it("is undefined when the supply is above the amount minted", () => {
    expect(burnedDvr(1_000n, 1_001n)).toBeUndefined();
  });
});
