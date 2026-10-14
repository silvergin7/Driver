"use client";

import { useBlock, useConnection, useReadContract } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import { driverTokenAbi } from "@/generated/contracts";
import { formatDvr } from "@/lib/format-dvr";

export function DvrBalance() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const block = useBlock({
    chainId: anvil.id,
    query: { enabled: onAnvil },
    watch: onAnvil,
  });
  const balance = useReadContract({
    abi: driverTokenAbi,
    address: contracts[anvil.id].driverToken,
    functionName: "balanceOf",
    args: connection.address === undefined ? undefined : [connection.address],
    blockNumber: block.data?.number,
    chainId: anvil.id,
    query: {
      enabled: onAnvil && connection.address !== undefined,
    },
  });

  if (!onAnvil || connection.address === undefined) {
    return null;
  }

  return (
    <section className="text-left">
      <p>
        {balance.isError
          ? "Balance unavailable."
          : balance.data === undefined
            ? "Loading balance…"
            : `${formatDvr(balance.data)} DVR`}
      </p>
    </section>
  );
}
