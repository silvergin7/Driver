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
    demoDriverClock: Address;
    officialPool: Address;
    roundSchedule: Address;
    cruiseControl: Address;
    degenDriver: Address;
    driverVote: Address;
  }
> = {
  [anvil.id]: {
    driverToken: getAddress(addresses["31337"].DriverToken),
    driverFaucet: getAddress(addresses["31337"].DriverFaucet),
    mockUsdc: getAddress(addresses["31337"].MockUSDC),
    mockUsdcFaucet: getAddress(addresses["31337"].MockUsdcFaucet),
    demoDriverClock: getAddress(addresses["31337"].DemoDriverClock),
    officialPool: getAddress(addresses["31337"].OfficialPool),
    roundSchedule: getAddress(addresses["31337"].RoundSchedule),
    cruiseControl: getAddress(addresses["31337"].CruiseControl),
    degenDriver: getAddress(addresses["31337"].DegenDriver),
    driverVote: getAddress(addresses["31337"].DriverVote),
  },
};
