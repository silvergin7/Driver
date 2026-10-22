import { getAddress, type Address } from "viem";

export const defaultSepoliaRpcUrl =
  "https://ethereum-sepolia-rpc.publicnode.com";

export type ChainName = "anvil" | "sepolia";

export function chainNameFrom(value: string | undefined): ChainName {
  if (value === undefined || value === "") {
    return "anvil";
  }
  if (value === "anvil" || value === "sepolia") {
    return value;
  }
  throw new Error(
    `NEXT_PUBLIC_CHAIN must be "anvil" or "sepolia". Received ${JSON.stringify(value)}.`,
  );
}

export function sepoliaRpcFrom(value: string | undefined): string {
  return value || defaultSepoliaRpcUrl;
}

export function pollingIntervalMs(chainName: ChainName): number {
  if (chainName === "anvil") {
    return 1_000;
  }
  return 4_000;
}

export const chainLabels = {
  anvil: "Anvil",
  sepolia: "Sepolia",
} as const;

export const contractFields = [
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

type ContractField = (typeof contractFields)[number];

export type ContractAddresses = {
  driverToken: Address;
  driverFaucet: Address;
  mockUsdc: Address;
  mockUsdcFaucet: Address;
  demoDriverClock: Address;
  taxSplitter: Address;
  officialPool: Address;
  roundSchedule: Address;
  cruiseControl: Address;
  degenDriver: Address;
  driverVote: Address;
};

const fieldKey: Record<ContractField, keyof ContractAddresses> = {
  DriverToken: "driverToken",
  DriverFaucet: "driverFaucet",
  MockUSDC: "mockUsdc",
  MockUsdcFaucet: "mockUsdcFaucet",
  DemoDriverClock: "demoDriverClock",
  TaxSplitter: "taxSplitter",
  OfficialPool: "officialPool",
  RoundSchedule: "roundSchedule",
  CruiseControl: "cruiseControl",
  DegenDriver: "degenDriver",
  DriverVote: "driverVote",
};

export function contractsFrom(
  book: object,
  chainId: number,
): ContractAddresses {
  const record = book as Record<string, unknown>;
  const entry = record[String(chainId)];
  if (typeof entry !== "object" || entry === null) {
    throw new Error(`addresses.json has no "${chainId}" entry.`);
  }
  const fields = entry as Record<string, unknown>;
  const addresses = {} as ContractAddresses;
  for (const name of contractFields) {
    const value = fields[name];
    if (typeof value !== "string") {
      throw new Error(`addresses.json chain "${chainId}" is missing ${name}.`);
    }
    try {
      addresses[fieldKey[name]] = getAddress(value);
    } catch {
      throw new Error(
        `addresses.json chain "${chainId}" field "${name}" is not an address.`,
      );
    }
  }
  return addresses;
}
