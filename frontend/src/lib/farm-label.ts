import type { Address } from "viem";

const names: Record<string, string> = {
  "500": "Cruise",
  "4000": "Highway",
  "8000": "Autobahn",
  "16000": "Drift",
};

export function farmLabel(aprBps: bigint, address: Address): string {
  return names[aprBps.toString()] ?? address;
}
