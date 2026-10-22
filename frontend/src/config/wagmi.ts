import { createConfig, http, type CreateConfigParameters } from "wagmi";
import { injected } from "wagmi/connectors";
import { chain, pollingInterval } from "./contracts";

const parameters = {
  chains: [chain],
  connectors: [injected()],
  multiInjectedProviderDiscovery: false,
  pollingInterval,
  ssr: true,
  transports: {
    [chain.id]: http(chain.rpcUrls.default.http[0]),
  },
} as CreateConfigParameters;

export const wagmiConfig = createConfig(parameters);
