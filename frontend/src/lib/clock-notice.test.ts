import { describe, expect, it } from "vitest";
import { showsPermanentClockNotice } from "./clock-notice";

describe("showsPermanentClockNotice", () => {
  it("hides the notice on Anvil", () => {
    expect(showsPermanentClockNotice("anvil")).toBe(false);
  });

  it("shows the notice on Sepolia and mainnet", () => {
    expect(showsPermanentClockNotice("sepolia")).toBe(true);
    expect(showsPermanentClockNotice("mainnet")).toBe(true);
  });
});
