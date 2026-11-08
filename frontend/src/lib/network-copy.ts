import type { ChainName } from "@/config/chain";

export function footerNotice(chainName: ChainName): string {
  if (chainName === "mainnet") {
    return "Driver (DVR) is a learning project. DVR and mUSDC have no real value. Network fees are real.";
  }
  return "Driver (DVR) is a learning project. DVR and mUSDC have no real value.";
}
