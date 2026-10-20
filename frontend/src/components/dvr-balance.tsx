"use client";

import { useConnection, useReadContract } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import { driverTokenAbi } from "@/generated/contracts";
import { BigStat } from "@/components/ui/big-stat";
import { formatDvr } from "@/lib/format-dvr";

export function DvrBalance() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const args =
    connection.address === undefined
      ? undefined
      : ([connection.address] as const);
  const balance = useReadContract({
    abi: driverTokenAbi,
    address: contracts[anvil.id].driverToken,
    args,
    chainId: anvil.id,
    functionName: "balanceOf",
    query: { enabled: onAnvil && connection.address !== undefined },
  });

  if (!onAnvil || connection.address === undefined) {
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
