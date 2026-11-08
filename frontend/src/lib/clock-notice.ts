import type { ChainName } from "@/config/chain";

export function showsPermanentClockNotice(chainName: ChainName): boolean {
  return chainName !== "anvil";
}
