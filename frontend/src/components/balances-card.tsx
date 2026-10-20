"use client";

import { useConnection } from "wagmi";
import { anvil } from "@/config/contracts";
import { DvrBalance } from "@/components/dvr-balance";
import { UsdcBalance } from "@/components/usdc-balance";
import { Card } from "@/components/ui/card";

export function BalancesCard() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;

  return (
    <Card className="w-fit self-center" title="Your balances">
      {!connection.isConnected ? (
        <p className="text-sm text-ink-muted">
          Connect a wallet in the header to see your balances.
        </p>
      ) : null}
      {connection.isConnected && !onAnvil ? (
        <p className="text-sm text-ink-muted">Switch to Anvil in the header.</p>
      ) : null}
      <div className={onAnvil ? "flex gap-6" : "hidden"}>
        <DvrBalance />
        <UsdcBalance />
      </div>
    </Card>
  );
}
