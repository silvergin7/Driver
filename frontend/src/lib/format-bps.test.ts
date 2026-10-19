import { describe, expect, it } from "vitest";
import { formatBps } from "./format-bps";

describe("formatBps", () => {
  it("formats a whole percent", () => {
    expect(formatBps(100n)).toBe("1%");
  });

  it("formats a half percent", () => {
    expect(formatBps(150n)).toBe("1.5%");
  });

  it("formats a larger whole percent", () => {
    expect(formatBps(4000n)).toBe("40%");
  });

  it("formats zero", () => {
    expect(formatBps(0n)).toBe("0%");
  });

  it("keeps a hundredth of a percent", () => {
    expect(formatBps(105n)).toBe("1.05%");
  });
});
