import type { ChainName } from "@/config/chain";

export function footerNotice(chainName: ChainName): string {
  if (chainName === "mainnet") {
    return "DVR and mUSDC have no real value. Network fees are real.";
  }
  return "DVR and mUSDC have no real value.";
}

export function roadmapNetwork(chainName: ChainName): string {
  if (chainName === "mainnet") {
    return "Ethereum";
  }
  if (chainName === "sepolia") {
    return "Sepolia";
  }
  return "Anvil";
}
