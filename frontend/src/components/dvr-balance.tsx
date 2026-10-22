"use client";

import { useConnection, useReadContract } from "wagmi";
import { chain, contracts } from "@/config/contracts";
import { driverTokenAbi } from "@/generated/contracts";
import { BigStat } from "@/components/ui/big-stat";
import { formatDvr } from "@/lib/format-dvr";

export function DvrBalance() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const args =
    connection.address === undefined
      ? undefined
      : ([connection.address] as const);
  const balance = useReadContract({
    abi: driverTokenAbi,
    address: contracts[chain.id].driverToken,
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
      ? formatDvr(balance.data)
      : balance.isError
        ? "Balance unavailable."
        : "Loading balance…";

  return <BigStat label="DVR" value={figure} />;
}
