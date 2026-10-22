"use client";

import type { Hex } from "viem";
import { chain } from "@/config/contracts";
import { transactionExplorer } from "@/lib/explorer";

export function TransactionLink({
  action,
  hash,
}: {
  action?: string;
  hash: Hex | undefined;
}) {
  if (hash === undefined) {
    return null;
  }
  const explorer = transactionExplorer(chain, hash);
  if (explorer.kind === "local") {
    return null;
  }
  const label =
    action === undefined
      ? `View on ${explorer.name}`
      : `View the ${action} on ${explorer.name}`;
  return (
    <a
      className="text-sm text-sign underline"
      href={explorer.href}
      target="_blank"
      rel="noreferrer"
    >
      {label}
    </a>
  );
}
