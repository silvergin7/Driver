import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { anvil } from "./contracts";

export const wagmiConfig = createConfig({
  chains: [anvil],
  connectors: [injected()],
  multiInjectedProviderDiscovery: false,
  pollingInterval: 1_000,
  ssr: true,
  transports: {
    [anvil.id]: http(anvil.rpcUrls.default.http[0]),
  },
});
