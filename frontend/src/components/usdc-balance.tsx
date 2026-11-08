"use client";

import { useConnection, useReadContract } from "wagmi";
import { chain, contracts } from "@/config/contracts";
import { mockUsdcAbi } from "@/generated/contracts";
import { TokenIcon } from "@/components/token-icon";
import { formatDisplayAmount } from "@/lib/format-display";

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
      ? formatDisplayAmount(balance.data, 6)
      : balance.isError
        ? "mUSDC balance unavailable."
        : "Loading mUSDC balance…";

  return (
    <div className="min-w-0">
      <p className="flex items-center gap-1.5 text-sm text-ink-muted">
        <TokenIcon token="musdc" className="h-5 w-5" />
        mUSDC
      </p>
      <p className="text-2xl font-semibold break-all text-ink tabular-nums">{figure}</p>
    </div>
  );
}
