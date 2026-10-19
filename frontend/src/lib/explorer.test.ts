import { getAddress, type Address } from "viem";
import { describe, expect, it } from "vitest";
import { addressExplorer } from "./explorer";

const token = "0xabcabcabcabcabcabcabcabcabcabcabcabcabca" as Address;

describe("addressExplorer", () => {
  it("marks a chain with no explorer as the local network", () => {
    expect(addressExplorer({}, token)).toEqual({ kind: "local" });
  });

  it("links an address on a chain that has an explorer", () => {
    expect(
      addressExplorer(
        {
          blockExplorers: {
            default: {
              name: "Etherscan",
              url: "https://sepolia.etherscan.io",
            },
          },
        },
        token,
      ),
    ).toEqual({
      kind: "link",
      href: `https://sepolia.etherscan.io/address/${getAddress(token)}`,
      name: "Etherscan",
    });
  });
});
