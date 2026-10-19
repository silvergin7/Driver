import { getAddress, zeroAddress, type Address } from "viem";

export function roundChoice(leader: Address): Address | undefined {
  if (getAddress(leader) === zeroAddress) {
    return undefined;
  }
  return getAddress(leader);
}
