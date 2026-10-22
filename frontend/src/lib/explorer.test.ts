import { getAddress, type Address } from "viem";
import { describe, expect, it } from "vitest";
import { addressExplorer, transactionExplorer } from "./explorer";

const token = "0xabcabcabcabcabcabcabcabcabcabcabcabcabca" as Address;
const hash = `0x${"11".repeat(32)}`;

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

const etherscan = {
  blockExplorers: {
    default: {
      name: "Etherscan",
      url: "https://sepolia.etherscan.io",
    },
  },
};

describe("transactionExplorer", () => {
  it("returns no link when the chain has no explorer", () => {
    expect(transactionExplorer({}, hash)).toEqual({ kind: "local" });
  });

  it("links a transaction on a chain that has an explorer", () => {
    expect(transactionExplorer(etherscan, hash)).toEqual({
      kind: "link",
      href: `https://sepolia.etherscan.io/tx/${hash}`,
      name: "Etherscan",
    });
  });

  it.each(["0x1234", "0xnote", "", `0x${"z".repeat(64)}`])(
    "rejects %j",
    (value) => {
      expect(explorerMessage(() => transactionExplorer(etherscan, value))).toBe(
        `Transaction hash is invalid. Received ${JSON.stringify(value)}.`,
      );
    },
  );
});

function explorerMessage(run: () => void): string {
  try {
    run();
  } catch (error) {
    if (error instanceof Error) {
      return error.message;
    }
    throw error;
  }
  throw new Error("expected a throw");
}
