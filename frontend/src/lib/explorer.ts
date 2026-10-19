import { getAddress, type Address } from "viem";

export type AddressExplorer =
  | { kind: "local" }
  | { kind: "link"; href: string; name: string };

export function addressExplorer(
  chain: {
    blockExplorers?: {
      default: { name: string; url: string };
    };
  },
  address: Address,
): AddressExplorer {
  const explorer = chain.blockExplorers?.default;
  if (explorer === undefined) {
    return { kind: "local" };
  }
  return {
    kind: "link",
    href: `${explorer.url}/address/${getAddress(address)}`,
    name: explorer.name,
  };
}
