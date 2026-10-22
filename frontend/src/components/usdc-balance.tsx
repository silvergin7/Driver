"use client";

import { useConnection, useReadContract } from "wagmi";
import { chain, contracts } from "@/config/contracts";
import { mockUsdcAbi } from "@/generated/contracts";
import { BigStat } from "@/components/ui/big-stat";
import { formatUsdc } from "@/lib/format-usdc";

export function UsdcBalance() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const args =
    connection.address === undefined
      ? undefined
      : ([connection.address] as const);
  const balance = useReadContract({
    abi: mockUsdcAbi,
    address: contracts[chain.id].mockUsdc,
    args,
    chainId: chain.id,
    functionName: "balanceOf",
    query: { enabled: onChain && connection.address !== undefined },
  });

  if (!onChain || connection.address === undefined) {
    return null;
  }

  const figure =
    balance.data !== undefined
      ? formatUsdc(balance.data)
      : balance.isError
        ? "mUSDC balance unavailable."
        : "Loading mUSDC balance…";

  return <BigStat label="mUSDC" value={figure} />;
}
