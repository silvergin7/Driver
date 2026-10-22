import { getAddress, isHex, type Address } from "viem";

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

export function transactionExplorer(
  chain: {
    blockExplorers?: {
      default: { name: string; url: string };
    };
  },
  hash: string,
): AddressExplorer {
  if (!isHex(hash) || hash.length !== 66) {
    throw new Error(
      `Transaction hash is invalid. Received ${JSON.stringify(hash)}.`,
    );
  }
  const explorer = chain.blockExplorers?.default;
  if (explorer === undefined) {
    return { kind: "local" };
  }
  return {
    kind: "link",
    href: `${explorer.url}/tx/${hash}`,
    name: explorer.name,
  };
}
