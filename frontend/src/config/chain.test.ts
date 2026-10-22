import { getAddress } from "viem";
import { describe, expect, it } from "vitest";
import addresses from "./addresses.json" with { type: "json" };
import {
  chainNameFrom,
  contractFields,
  contractsFrom,
  defaultSepoliaRpcUrl,
  pollingIntervalMs,
  sepoliaRpcFrom,
} from "./chain";

const sample = "0xabcabcabcabcabcabcabcabcabcabcabcabcabca";

function message(run: () => void): string {
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

function deployment(
  chainId: number,
  patch: Record<string, unknown> = {},
): Record<string, unknown> {
  const entry: Record<string, unknown> = {};
  for (const name of contractFields) {
    entry[name] = sample;
  }
  return { [String(chainId)]: { ...entry, ...patch } };
}

describe("chainNameFrom", () => {
  it("selects Anvil when the value is unset or empty", () => {
    expect(chainNameFrom(undefined)).toBe("anvil");
    expect(chainNameFrom("")).toBe("anvil");
  });

  it("accepts the exact chain names", () => {
    expect(chainNameFrom("anvil")).toBe("anvil");
    expect(chainNameFrom("sepolia")).toBe("sepolia");
  });

  it.each([
    ["Anvil", 'Received "Anvil".'],
    ["SEPOLIA", 'Received "SEPOLIA".'],
    [" sepolia", 'Received " sepolia".'],
    ["sepolia ", 'Received "sepolia ".'],
    ["anvil ", 'Received "anvil ".'],
    ["sepolia\r", 'Received "sepolia\\r".'],
  ])("rejects %j", (value, received) => {
    expect(message(() => chainNameFrom(value))).toBe(
      `NEXT_PUBLIC_CHAIN must be "anvil" or "sepolia". ${received}`,
    );
  });
});

describe("sepoliaRpcFrom", () => {
  it("uses the public default when the value is unset or empty", () => {
    expect(sepoliaRpcFrom(undefined)).toBe(defaultSepoliaRpcUrl);
    expect(sepoliaRpcFrom("")).toBe(defaultSepoliaRpcUrl);
  });

  it("keeps a configured url", () => {
    expect(sepoliaRpcFrom("http://127.0.0.1:8545")).toBe(
      "http://127.0.0.1:8545",
    );
  });
});

describe("pollingIntervalMs", () => {
  it("polls Anvil every second and Sepolia every four seconds", () => {
    expect(pollingIntervalMs("anvil")).toBe(1_000);
    expect(pollingIntervalMs("sepolia")).toBe(4_000);
  });
});

describe("contractsFrom", () => {
  it("checksums a lowercase address and ignores extra fields", () => {
    const read = contractsFrom(
      deployment(31337, { CruiseFarm: sample }),
      31337,
    );
    expect(read.driverToken).toBe(getAddress(sample));
    expect(read.demoDriverClock).toBe(getAddress(sample));
    expect(read).not.toHaveProperty("CruiseFarm");
  });

  it("rejects a missing chain entry", () => {
    expect(message(() => contractsFrom({}, 31337))).toBe(
      'addresses.json has no "31337" entry.',
    );
    expect(message(() => contractsFrom({ "11155111": null }, 11155111))).toBe(
      'addresses.json has no "11155111" entry.',
    );
  });

  it.each([31337, 11155111])(
    "requires DemoDriverClock on %s",
    (chainId) => {
      const book = deployment(chainId);
      const entry = book[String(chainId)] as Record<string, unknown>;
      delete entry.DemoDriverClock;
      entry.DriverClock = sample;
      expect(message(() => contractsFrom(book, chainId))).toBe(
        `addresses.json chain "${chainId}" is missing DemoDriverClock.`,
      );
    },
  );

  it("requires every named contract", () => {
    const book = deployment(11155111);
    const entry = book["11155111"] as Record<string, unknown>;
    delete entry.DriverVote;
    expect(message(() => contractsFrom(book, 11155111))).toBe(
      'addresses.json chain "11155111" is missing DriverVote.',
    );
  });

  it("rejects a field that is not an address", () => {
    expect(
      message(() =>
        contractsFrom(deployment(31337, { DriverToken: "0x1234" }), 31337),
      ),
    ).toBe(
      'addresses.json chain "31337" field "DriverToken" is not an address.',
    );
  });

  it("reads both committed deployments", () => {
    const anvil = contractsFrom(addresses, 31337);
    const sepolia = contractsFrom(addresses, 11155111);
    expect(anvil.demoDriverClock).toBe(
      getAddress(addresses["31337"].DemoDriverClock),
    );
    expect(sepolia.cruiseControl).toBe(
      getAddress(addresses["11155111"].CruiseControl),
    );
    expect(sepolia.driverVote).toBe(
      getAddress(addresses["11155111"].DriverVote),
    );
  });
});
