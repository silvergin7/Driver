import { foundry, mainnet, sepolia } from "viem/chains";
import addresses from "./addresses.json" with { type: "json" };
import {
  chainLabels,
  chainNameFrom,
  contractsFrom,
  mainnetRpcFrom,
  pollingIntervalMs,
  sepoliaRpcFrom,
  type ContractAddresses,
} from "./chain";

export const chainName = chainNameFrom(process.env.NEXT_PUBLIC_CHAIN);

const anvilRpcUrl =
  process.env.NEXT_PUBLIC_ANVIL_RPC_URL || "http://127.0.0.1:8545";

const anvil = {
  ...foundry,
  rpcUrls: {
    default: {
      http: [anvilRpcUrl],
    },
  },
};

const sepoliaChain = {
  ...sepolia,
  rpcUrls: {
    default: {
      http: [sepoliaRpcFrom(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL)],
    },
  },
};

const mainnetChain = {
  ...mainnet,
  rpcUrls: {
    default: {
      http: [mainnetRpcFrom(process.env.NEXT_PUBLIC_MAINNET_RPC_URL)],
    },
  },
};

function selectedChain() {
  if (chainName === "mainnet") {
    return mainnetChain;
  }
  if (chainName === "sepolia") {
    return sepoliaChain;
  }
  return anvil;
}

export const chain = selectedChain();

export const chainLabel = chainLabels[chainName];

export const pollingInterval = pollingIntervalMs(chainName);

export const contracts: { [id: number]: ContractAddresses } = {
  [chain.id]: contractsFrom(addresses, chain.id),
};
