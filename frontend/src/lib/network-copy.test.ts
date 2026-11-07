import { describe, expect, it } from "vitest";
import { footerNotice, roadmapNetwork } from "./network-copy";

describe("footerNotice", () => {
  it("says the tokens have no real value", () => {
    expect(footerNotice("anvil")).toBe("DVR and mUSDC have no real value.");
    expect(footerNotice("sepolia")).toBe("DVR and mUSDC have no real value.");
  });

  it("adds the fee warning on mainnet", () => {
    expect(footerNotice("mainnet")).toBe(
      "DVR and mUSDC have no real value. Network fees are real.",
    );
  });
});

describe("roadmapNetwork", () => {
  it("names the chain in the lesson", () => {
    expect(roadmapNetwork("anvil")).toBe("Anvil");
    expect(roadmapNetwork("sepolia")).toBe("Sepolia");
    expect(roadmapNetwork("mainnet")).toBe("Ethereum");
  });
});
