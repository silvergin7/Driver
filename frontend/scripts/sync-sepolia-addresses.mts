import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  BroadcastAddressError,
  assertHasAnvil,
  deployedAddresses,
  readAddressFile,
  writeAddressBook,
} from "./broadcast-addresses.mts";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const broadcastPath = resolve(
  scriptDir,
  "../../contracts/broadcast/DeployDriver.s.sol/11155111/run-latest.json",
);
const outputPath = resolve(scriptDir, "../src/config/addresses.json");

export async function syncSepoliaAddresses(
  broadcastFile: string,
  outputFile: string,
): Promise<void> {
  const broadcast: unknown = JSON.parse(await readFile(broadcastFile, "utf8"));
  const addresses = deployedAddresses(broadcast, 11155111);
  const existing = await readAddressFile(outputFile);
  assertHasAnvil(existing);
  await mkdir(dirname(outputFile), { recursive: true });
  await writeFile(
    outputFile,
    writeAddressBook(existing, "11155111", addresses),
  );
}

const entry = process.argv[1];
const isDirect =
  entry !== undefined &&
  import.meta.url === pathToFileURL(resolve(entry)).href;

if (isDirect) {
  try {
    await syncSepoliaAddresses(broadcastPath, outputPath);
  } catch (error) {
    if (error instanceof BroadcastAddressError) {
      console.error(error.message);
      process.exit(1);
    }
    throw error;
  }
}
