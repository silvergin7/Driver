import { getAddress, type Address } from "viem";
import { foundry } from "viem/chains";
import addresses from "./addresses.json" with { type: "json" };

const anvilRpcUrl =
  process.env.NEXT_PUBLIC_ANVIL_RPC_URL || "http://127.0.0.1:8545";

export const anvil = {
  ...foundry,
  rpcUrls: {
    default: {
      http: [anvilRpcUrl],
    },
  },
};

export const contracts: Record<
  typeof anvil.id,
  {
    driverToken: Address;
    driverFaucet: Address;
    mockUsdc: Address;
    mockUsdcFaucet: Address;
  }
> = {
  [anvil.id]: {
    driverToken: getAddress(addresses["31337"].DriverToken),
    driverFaucet: getAddress(addresses["31337"].DriverFaucet),
    mockUsdc: getAddress(addresses["31337"].MockUSDC),
    mockUsdcFaucet: getAddress(addresses["31337"].MockUsdcFaucet),
  },
};
