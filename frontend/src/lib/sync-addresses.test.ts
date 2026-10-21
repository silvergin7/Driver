import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  BroadcastAddressError,
  assertHasAnvil,
  deployedAddresses,
  writeAddressBook,
} from "../../scripts/broadcast-addresses.mts";
import { syncAnvilAddresses } from "../../scripts/sync-anvil-addresses.mts";

const contractNames = [
  "DriverToken",
  "DriverFaucet",
  "MockUSDC",
  "MockUsdcFaucet",
  "DemoDriverClock",
  "TaxSplitter",
  "OfficialPool",
  "RoundSchedule",
  "CruiseControl",
  "DegenDriver",
  "DriverVote",
] as const;

const farmNames = [
  "CruiseFarm",
  "HighwayFarm",
  "AutobahnFarm",
  "DriftFarm",
] as const;

const deployerArgument = `0x${"ee".repeat(20)}`;

function address(byte: number): string {
  return `0x${byte.toString(16).padStart(2, "0").repeat(20)}`;
}

type FixtureTransaction = {
  transactionType: string;
  contractName?: string;
  contractAddress?: string;
  function?: string;
  arguments?: string[];
};

function creates(chainId: number) {
  const named: FixtureTransaction[] = contractNames.map((name, index) => ({
    transactionType: "CREATE",
    contractName: name,
    contractAddress: address(index + 1),
  }));
  const farms: FixtureTransaction[] = [8, 9, 10, 11].map((byte) => ({
    transactionType: "CREATE",
    contractName: "MockFarm",
    contractAddress: address(byte),
  }));
  const poolIndex = named.findIndex(
    (create) => create.contractName === "OfficialPool",
  );
  const transactions: FixtureTransaction[] = [
    ...named.slice(0, poolIndex + 1),
    ...farms,
    ...named.slice(poolIndex + 1),
    {
      transactionType: "CALL",
      contractName: "DegenDriver",
      function: "setBallot(address)",
    },
  ];
  return {
    chain: chainId,
    receipts: transactions.map(() => ({ status: "0x1" })),
    transactions,
  };
}

function anvilBroadcast() {
  return creates(31337);
}

describe("deployedAddresses", () => {
  it("throws when a receipt failed", () => {
    const broadcast = anvilBroadcast();
    broadcast.receipts = broadcast.receipts.map(() => ({ status: "0x0" }));
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      BroadcastAddressError,
    );
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      "Broadcast receipt was not successful.",
    );
  });

  it("throws when the broadcast has no receipts", () => {
    expect(() =>
      deployedAddresses({ chain: 31337, receipts: [], transactions: [] }, 31337),
    ).toThrow("Broadcast has no receipts.");
  });

  it("throws when a named create is missing", () => {
    const broadcast = anvilBroadcast();
    broadcast.transactions = broadcast.transactions.filter(
      (transaction) => transaction.contractName !== "DriverVote",
    );
    broadcast.receipts = broadcast.transactions.map(() => ({ status: "0x1" }));
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      "Missing contract in the broadcast: DriverVote.",
    );
  });

  it("throws when a contract is created twice", () => {
    const broadcast = anvilBroadcast();
    const token = broadcast.transactions.find(
      (transaction) => transaction.contractName === "DriverToken",
    );
    broadcast.transactions.push({ ...token!, contractAddress: address(20) });
    broadcast.receipts.push({ status: "0x1" });
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      "Duplicate contract in the broadcast: DriverToken.",
    );
  });

  it("throws when the broadcast creates an unexpected contract", () => {
    const broadcast = anvilBroadcast();
    const clock = broadcast.transactions.find(
      (transaction) => transaction.contractName === "DemoDriverClock",
    );
    clock!.contractName = "DriverClock";
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      "Unexpected contract in the broadcast: DriverClock.",
    );
  });

  it("throws when the farm count is not four", () => {
    const broadcast = anvilBroadcast();
    const drop = broadcast.transactions.findIndex(
      (transaction) =>
        transaction.contractName === "MockFarm" &&
        transaction.contractAddress === address(11),
    );
    broadcast.transactions.splice(drop, 1);
    broadcast.receipts.pop();
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      "Expected exactly four MockFarm creates, found 3.",
    );

    const extra = anvilBroadcast();
    extra.transactions.push({
      transactionType: "CREATE",
      contractName: "MockFarm",
      contractAddress: address(21),
    });
    extra.receipts.push({ status: "0x1" });
    expect(() => deployedAddresses(extra, 31337)).toThrow(
      "Expected exactly four MockFarm creates, found 5.",
    );
  });

  it("maps the four farms in broadcast order", () => {
    const addresses = deployedAddresses(anvilBroadcast(), 31337);
    expect(addresses.CruiseFarm).toBe(address(8));
    expect(addresses.HighwayFarm).toBe(address(9));
    expect(addresses.AutobahnFarm).toBe(address(10));
    expect(addresses.DriftFarm).toBe(address(11));
    expect(Object.keys(addresses)).toEqual([
      ...contractNames.slice(0, 7),
      ...farmNames,
      ...contractNames.slice(7),
    ]);
  });

  it("lowercases addresses", () => {
    const broadcast = anvilBroadcast();
    const token = broadcast.transactions.find(
      (transaction) => transaction.contractName === "DriverToken",
    );
    token!.contractAddress = `0x${"Ab".repeat(20)}`;
    expect(deployedAddresses(broadcast, 31337).DriverToken).toBe(
      `0x${"ab".repeat(20)}`,
    );
  });

  it("throws when the chain id does not match", () => {
    expect(() => deployedAddresses(anvilBroadcast(), 11155111)).toThrow(
      "Broadcast chain is 31337, expected 11155111.",
    );
  });

  it("throws when a create address is not 20 bytes", () => {
    const broadcast = anvilBroadcast();
    const token = broadcast.transactions.find(
      (transaction) => transaction.contractName === "DriverToken",
    );
    token!.contractAddress = "0x1234";
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      /^Invalid address for DriverToken\.$/,
    );
  });

  it("throws when a create is missing a contract name or address", () => {
    const missingName = anvilBroadcast();
    const named = missingName.transactions.find(
      (transaction) => transaction.contractName === "DriverToken",
    );
    delete named!.contractName;
    expect(() => deployedAddresses(missingName, 31337)).toThrow(
      /^Broadcast create is missing a contract name or address\.$/,
    );

    const missingAddress = anvilBroadcast();
    const addressed = missingAddress.transactions.find(
      (transaction) => transaction.contractName === "DriverToken",
    );
    delete addressed!.contractAddress;
    expect(() => deployedAddresses(missingAddress, 31337)).toThrow(
      /^Broadcast create is missing a contract name or address\.$/,
    );
  });

  it("throws when the broadcast has no transactions", () => {
    const broadcast = anvilBroadcast();
    broadcast.transactions = [];
    expect(() => deployedAddresses(broadcast, 31337)).toThrow(
      /^Broadcast has no transactions\.$/,
    );
  });

  it("leaves a deployer argument out of the address book", () => {
    const broadcast = anvilBroadcast();
    const token = broadcast.transactions.find(
      (transaction) => transaction.contractName === "DriverToken",
    );
    token!.arguments = [deployerArgument];
    const text = JSON.stringify(deployedAddresses(broadcast, 31337));
    expect(text.includes(deployerArgument)).toBe(false);
  });
});

describe("writeAddressBook", () => {
  it("keeps a Sepolia entry byte-identical when Anvil is rewritten", () => {
    const anvil = deployedAddresses(anvilBroadcast(), 31337);
    const sepolia = deployedAddresses(creates(11155111), 11155111);
    const combined = writeAddressBook(
      writeAddressBook(null, "31337", anvil),
      "11155111",
      sepolia,
    );
    expect(writeAddressBook(combined, "31337", anvil)).toBe(combined);
  });

  it("keeps the Anvil entry byte-identical when Sepolia is rewritten", () => {
    const anvil = deployedAddresses(anvilBroadcast(), 31337);
    const sepolia = deployedAddresses(creates(11155111), 11155111);
    const combined = writeAddressBook(
      writeAddressBook(null, "31337", anvil),
      "11155111",
      sepolia,
    );
    expect(writeAddressBook(combined, "11155111", sepolia)).toBe(combined);
  });

  it("throws when the Anvil deployment is absent", () => {
    expect(() => assertHasAnvil(null)).toThrow(BroadcastAddressError);
    expect(() => assertHasAnvil("{}\n")).toThrow(
      "Address file is missing the Anvil deployment.",
    );
    expect(() =>
      assertHasAnvil(
        writeAddressBook(
          null,
          "31337",
          deployedAddresses(anvilBroadcast(), 31337),
        ),
      ),
    ).not.toThrow();
  });
});

describe("syncAnvilAddresses", () => {
  it("throws when the broadcast file is not a successful deploy", async () => {
    const directory = await mkdtemp(join(tmpdir(), "driver-sync-"));
    const broadcastFile = join(directory, "broadcast.json");
    const outputFile = join(directory, "addresses.json");
    await writeFile(broadcastFile, "{}\n");
    await expect(syncAnvilAddresses(broadcastFile, outputFile)).rejects.toThrow(
      BroadcastAddressError,
    );
  });

  it("rewrites Anvil and leaves the other chain in place", async () => {
    const directory = await mkdtemp(join(tmpdir(), "driver-sync-"));
    const broadcastFile = join(directory, "broadcast.json");
    const outputFile = join(directory, "addresses.json");
    const anvil = deployedAddresses(anvilBroadcast(), 31337);
    const sepolia = deployedAddresses(creates(11155111), 11155111);
    const combined = writeAddressBook(
      writeAddressBook(null, "31337", anvil),
      "11155111",
      sepolia,
    );
    await writeFile(broadcastFile, `${JSON.stringify(anvilBroadcast())}\n`);
    await writeFile(outputFile, combined);
    await syncAnvilAddresses(broadcastFile, outputFile);
    expect(await readFile(outputFile, "utf8")).toBe(combined);
  });
});
