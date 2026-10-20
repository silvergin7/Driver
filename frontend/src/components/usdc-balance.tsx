"use client";

import { useConnection, useReadContract } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import { mockUsdcAbi } from "@/generated/contracts";
import { BigStat } from "@/components/ui/big-stat";
import { formatUsdc } from "@/lib/format-usdc";

export function UsdcBalance() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const args =
    connection.address === undefined
      ? undefined
      : ([connection.address] as const);
  const balance = useReadContract({
    abi: mockUsdcAbi,
    address: contracts[anvil.id].mockUsdc,
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
      ? formatUsdc(balance.data)
      : balance.isError
        ? "mUSDC balance unavailable."
        : "Loading mUSDC balance…";

  return <BigStat label="mUSDC" value={figure} />;
}
