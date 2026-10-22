import { describe, expect, it } from "vitest";
import { switchPrompt } from "./switch-prompt";

const details = [
  "to claim.",
  "to lock and vote.",
  "in the header.",
  "to swap.",
  "to see the funds.",
  "to harvest.",
] as const;

describe("switchPrompt", () => {
  it("names the chain on the button", () => {
    expect(switchPrompt("Anvil")).toBe("Switch to Anvil");
    expect(switchPrompt("Sepolia")).toBe("Switch to Sepolia");
  });

  it.each(details)("keeps the Anvil sentence for %s", (detail) => {
    expect(switchPrompt("Anvil", detail)).toBe(`Switch to Anvil ${detail}`);
  });

  it.each(details)("names Sepolia in the sentence for %s", (detail) => {
    expect(switchPrompt("Sepolia", detail)).toBe(`Switch to Sepolia ${detail}`);
  });
});
