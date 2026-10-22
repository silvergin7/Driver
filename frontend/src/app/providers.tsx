"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { WagmiProvider } from "wagmi";
import { wagmiConfig } from "@/config/wagmi";
import { useChainBlockRefresh } from "@/hooks/use-chain-block";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <ChainRefresh>{children}</ChainRefresh>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

function ChainRefresh({ children }: { children: ReactNode }) {
  useChainBlockRefresh();
  return children;
}
