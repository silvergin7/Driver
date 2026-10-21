import { readFile } from "node:fs/promises";

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

type ContractName = (typeof contractNames)[number];
type FarmName = (typeof farmNames)[number];
export type DeployedName = ContractName | FarmName;
export type DeployedAddresses = Record<DeployedName, string>;

type BroadcastTransaction = {
  transactionType?: string;
  contractName?: string;
  contractAddress?: string;
};

type BroadcastReceipt = {
  status?: string;
};

type BroadcastFile = {
  chain?: number;
  transactions?: BroadcastTransaction[];
  receipts?: BroadcastReceipt[];
};

type AddressBook = Record<string, Record<string, string>>;

const addressPattern = /^0x[0-9a-fA-F]{40}$/;

export class BroadcastAddressError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BroadcastAddressError";
  }
}

function asBroadcast(value: unknown): BroadcastFile {
  if (!value || typeof value !== "object") {
    throw new BroadcastAddressError("Broadcast has no receipts.");
  }
  return value as BroadcastFile;
}

function isContractName(name: string): name is ContractName {
  return (contractNames as readonly string[]).includes(name);
}

export function deployedAddresses(
  value: unknown,
  expectedChainId: number,
): DeployedAddresses {
  const broadcast = asBroadcast(value);
  const receipts = broadcast.receipts;
  if (!receipts || receipts.length === 0) {
    throw new BroadcastAddressError("Broadcast has no receipts.");
  }
  for (const receipt of receipts) {
    if (receipt.status !== "0x1") {
      throw new BroadcastAddressError("Broadcast receipt was not successful.");
    }
  }
  if (broadcast.chain !== expectedChainId) {
    throw new BroadcastAddressError(
      `Broadcast chain is ${String(broadcast.chain)}, expected ${expectedChainId}.`,
    );
  }

  const transactions = broadcast.transactions;
  if (!transactions || transactions.length === 0) {
    throw new BroadcastAddressError("Broadcast has no transactions.");
  }

  const found = new Map<ContractName, string>();
  const farms: string[] = [];
  for (const transaction of transactions) {
    if (
      transaction.transactionType !== "CREATE" &&
      transaction.transactionType !== "CREATE2"
    ) {
      continue;
    }
    const name = transaction.contractName;
    const deployed = transaction.contractAddress;
    if (!name || !deployed) {
      throw new BroadcastAddressError(
        "Broadcast create is missing a contract name or address.",
      );
    }
    if (!addressPattern.test(deployed)) {
      throw new BroadcastAddressError(`Invalid address for ${name}.`);
    }
    const address = deployed.toLowerCase();
    if (name === "MockFarm") {
      farms.push(address);
      continue;
    }
    if (!isContractName(name)) {
      throw new BroadcastAddressError(
        `Unexpected contract in the broadcast: ${name}.`,
      );
    }
    if (found.has(name)) {
      throw new BroadcastAddressError(
        `Duplicate contract in the broadcast: ${name}.`,
      );
    }
    found.set(name, address);
  }

  if (farms.length !== farmNames.length) {
    throw new BroadcastAddressError(
      `Expected exactly four MockFarm creates, found ${farms.length}.`,
    );
  }

  const farmAddresses = Object.fromEntries(
    farmNames.map((name, index) => [name, farms[index]]),
  ) as Record<FarmName, string>;

  return {
    DriverToken: requireAddress(found, "DriverToken"),
    DriverFaucet: requireAddress(found, "DriverFaucet"),
    MockUSDC: requireAddress(found, "MockUSDC"),
    MockUsdcFaucet: requireAddress(found, "MockUsdcFaucet"),
    DemoDriverClock: requireAddress(found, "DemoDriverClock"),
    TaxSplitter: requireAddress(found, "TaxSplitter"),
    OfficialPool: requireAddress(found, "OfficialPool"),
    ...farmAddresses,
    RoundSchedule: requireAddress(found, "RoundSchedule"),
    CruiseControl: requireAddress(found, "CruiseControl"),
    DegenDriver: requireAddress(found, "DegenDriver"),
    DriverVote: requireAddress(found, "DriverVote"),
  };
}

function requireAddress(
  found: Map<ContractName, string>,
  name: ContractName,
): string {
  const deployed = found.get(name);
  if (!deployed) {
    throw new BroadcastAddressError(
      `Missing contract in the broadcast: ${name}.`,
    );
  }
  return deployed;
}

export function assertHasAnvil(existingJson: string | null): void {
  if (!existingJson) {
    throw new BroadcastAddressError(
      "Address file is missing the Anvil deployment.",
    );
  }
  const parsed: unknown = JSON.parse(existingJson);
  if (
    !parsed ||
    typeof parsed !== "object" ||
    !("31337" in parsed) ||
    typeof parsed["31337"] !== "object" ||
    parsed["31337"] === null
  ) {
    throw new BroadcastAddressError(
      "Address file is missing the Anvil deployment.",
    );
  }
}

function isMissingFile(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}

export async function readAddressFile(path: string): Promise<string | null> {
  try {
    return await readFile(path, "utf8");
  } catch (error) {
    if (!isMissingFile(error)) {
      throw error;
    }
    return null;
  }
}

export function writeAddressBook(
  existingJson: string | null,
  chainId: string,
  addresses: DeployedAddresses,
): string {
  const existing: AddressBook =
    existingJson === null ? {} : (JSON.parse(existingJson) as AddressBook);
  const merged: AddressBook = { ...existing, [chainId]: addresses };
  return `${JSON.stringify(merged, null, 2)}\n`;
}
