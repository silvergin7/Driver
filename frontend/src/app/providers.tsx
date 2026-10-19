"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { WagmiProvider } from "wagmi";
import { wagmiConfig } from "@/config/wagmi";
import { useAnvilBlockRefresh } from "@/hooks/use-anvil-block";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <AnvilRefresh>{children}</AnvilRefresh>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

function AnvilRefresh({ children }: { children: ReactNode }) {
  useAnvilBlockRefresh();
  return children;
}
