"use client";

import { useConnection, useReadContract } from "wagmi";
import { chain, contracts } from "@/config/contracts";
import { driverTokenAbi } from "@/generated/contracts";
import { TokenIcon } from "@/components/token-icon";
import { formatDisplayAmount } from "@/lib/format-display";

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
      ? formatDisplayAmount(balance.data, 18)
      : balance.isError
        ? "Balance unavailable."
        : "Loading balance…";

  return (
    <div className="min-w-0">
      <p className="flex items-center gap-1.5 text-sm text-ink-muted">
        <TokenIcon token="dvr" className="h-5 w-7" />
        DVR
      </p>
      <p className="text-2xl font-semibold break-all text-ink tabular-nums">{figure}</p>
    </div>
  );
}
