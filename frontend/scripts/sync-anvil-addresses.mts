import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const contractNames = [
  "DriverToken",
  "DriverFaucet",
  "MockUSDC",
  "MockUsdcFaucet",
  "DemoDriverClock",
  "TaxSplitter",
  "OfficialPool",
  "CruiseControl",
  "DegenDriver",
] as const;

const farmNames = [
  "CruiseFarm",
  "HighwayFarm",
  "AutobahnFarm",
  "DriftFarm",
] as const;

type ContractName = (typeof contractNames)[number];
type FarmName = (typeof farmNames)[number];

type BroadcastTransaction = {
  transactionType?: string;
  contractName?: string;
  contractAddress?: string;
};

type BroadcastReceipt = {
  status?: string;
};

type BroadcastFile = {
  transactions?: BroadcastTransaction[];
  receipts?: BroadcastReceipt[];
};

const addressPattern = /^0x[0-9a-fA-F]{40}$/;

const scriptDir = dirname(fileURLToPath(import.meta.url));
const broadcastPath = resolve(
  scriptDir,
  "../../contracts/broadcast/DeployDriverToken.s.sol/31337/run-latest.json",
);
const outputPath = resolve(scriptDir, "../src/config/addresses.json");

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

function isContractName(name: string): name is ContractName {
  return (contractNames as readonly string[]).includes(name);
}

export async function syncAnvilAddresses(
  broadcastFile: string,
  outputFile: string,
): Promise<void> {
  const broadcast = JSON.parse(
    await readFile(broadcastFile, "utf8"),
  ) as BroadcastFile;
  const receipts = broadcast.receipts;
  if (!receipts || receipts.length === 0) {
    fail("Broadcast has no receipts.");
  }
  for (const receipt of receipts) {
    if (receipt.status !== "0x1") {
      fail("Broadcast receipt was not successful.");
    }
  }

  const transactions = broadcast.transactions;
  if (!transactions || transactions.length === 0) {
    fail("Broadcast has no transactions.");
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
      fail("Broadcast create is missing a contract name or address.");
    }
    if (!addressPattern.test(deployed)) {
      fail(`Invalid address for ${name}.`);
    }
    const address = deployed.toLowerCase();
    if (name === "MockFarm") {
      farms.push(address);
      continue;
    }
    if (!isContractName(name)) {
      fail(`Unexpected contract in the broadcast: ${name}.`);
    }
    if (found.has(name)) {
      fail(`Duplicate contract in the broadcast: ${name}.`);
    }
    found.set(name, address);
  }

  if (farms.length !== farmNames.length) {
    fail(`Expected exactly four MockFarm creates, found ${farms.length}.`);
  }

  const farmAddresses = Object.fromEntries(
    farmNames.map((name, index) => [name, farms[index]]),
  ) as Record<FarmName, string>;

  const addresses = {
    DriverToken: requireAddress(found, "DriverToken"),
    DriverFaucet: requireAddress(found, "DriverFaucet"),
    MockUSDC: requireAddress(found, "MockUSDC"),
    MockUsdcFaucet: requireAddress(found, "MockUsdcFaucet"),
    DemoDriverClock: requireAddress(found, "DemoDriverClock"),
    TaxSplitter: requireAddress(found, "TaxSplitter"),
    OfficialPool: requireAddress(found, "OfficialPool"),
    ...farmAddresses,
    CruiseControl: requireAddress(found, "CruiseControl"),
    DegenDriver: requireAddress(found, "DegenDriver"),
  };

  await mkdir(dirname(outputFile), { recursive: true });
  await writeFile(
    outputFile,
    `${JSON.stringify({ "31337": addresses }, null, 2)}\n`,
  );
}

function requireAddress(
  found: Map<ContractName, string>,
  name: ContractName,
): string {
  const deployed = found.get(name);
  if (!deployed) {
    fail(`Missing contract in the broadcast: ${name}.`);
  }
  return deployed;
}

const entry = process.argv[1];
const isDirect =
  entry !== undefined &&
  import.meta.url === pathToFileURL(resolve(entry)).href;

if (isDirect) {
  await syncAnvilAddresses(broadcastPath, outputPath);
}
