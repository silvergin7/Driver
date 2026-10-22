import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { chain } from "./contracts";

export const wagmiConfig = createConfig({
  chains: [chain],
  connectors: [injected()],
  multiInjectedProviderDiscovery: false,
  pollingInterval: 1_000,
  ssr: true,
  transports: {
    [chain.id]: http(chain.rpcUrls.default.http[0]),
  },
});
