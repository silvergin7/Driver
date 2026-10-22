"use client";

import { useConnection } from "wagmi";
import { chain, chainLabel } from "@/config/contracts";
import { switchPrompt } from "@/lib/switch-prompt";
import { DvrBalance } from "@/components/dvr-balance";
import { UsdcBalance } from "@/components/usdc-balance";
import { Card } from "@/components/ui/card";

export function BalancesCard() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;

  return (
    <Card className="w-fit self-center" title="Your balances">
      {!connection.isConnected ? (
        <p className="text-sm text-ink-muted">
          Connect a wallet in the header to see your balances.
        </p>
      ) : null}
      {connection.isConnected && !onChain ? (
        <p className="text-sm text-ink-muted">
          {switchPrompt(chainLabel, "in the header.")}
        </p>
      ) : null}
      <div className={onChain ? "flex gap-6" : "hidden"}>
        <DvrBalance />
        <UsdcBalance />
      </div>
    </Card>
  );
}
