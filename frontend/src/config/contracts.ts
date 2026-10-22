import { getAddress, type Address } from "viem";
import { foundry } from "viem/chains";
import addresses from "./addresses.json" with { type: "json" };

const anvilRpcUrl =
  process.env.NEXT_PUBLIC_ANVIL_RPC_URL || "http://127.0.0.1:8545";

export const chain = {
  ...foundry,
  rpcUrls: {
    default: {
      http: [anvilRpcUrl],
    },
  },
};

export const chainLabel = "Anvil";

export const contracts: Record<
  typeof chain.id,
  {
    driverToken: Address;
    driverFaucet: Address;
    mockUsdc: Address;
    mockUsdcFaucet: Address;
    demoDriverClock: Address;
    taxSplitter: Address;
    officialPool: Address;
    roundSchedule: Address;
    cruiseControl: Address;
    degenDriver: Address;
    driverVote: Address;
  }
> = {
  [chain.id]: {
    driverToken: getAddress(addresses["31337"].DriverToken),
    driverFaucet: getAddress(addresses["31337"].DriverFaucet),
    mockUsdc: getAddress(addresses["31337"].MockUSDC),
    mockUsdcFaucet: getAddress(addresses["31337"].MockUsdcFaucet),
    demoDriverClock: getAddress(addresses["31337"].DemoDriverClock),
    taxSplitter: getAddress(addresses["31337"].TaxSplitter),
    officialPool: getAddress(addresses["31337"].OfficialPool),
    roundSchedule: getAddress(addresses["31337"].RoundSchedule),
    cruiseControl: getAddress(addresses["31337"].CruiseControl),
    degenDriver: getAddress(addresses["31337"].DegenDriver),
    driverVote: getAddress(addresses["31337"].DriverVote),
  },
};
