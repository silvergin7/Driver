import { describe, expect, it } from "vitest";
import { footerNotice } from "./network-copy";

describe("footerNotice", () => {
  it("says this is a learning project and the tokens have no real value", () => {
    expect(footerNotice("anvil")).toBe(
      "Driver (DVR) is a learning project. DVR and mUSDC have no real value.",
    );
    expect(footerNotice("sepolia")).toBe(
      "Driver (DVR) is a learning project. DVR and mUSDC have no real value.",
    );
  });

  it("adds the fee warning on mainnet", () => {
    expect(footerNotice("mainnet")).toBe(
      "Driver (DVR) is a learning project. DVR and mUSDC have no real value. Network fees are real.",
    );
  });
});
