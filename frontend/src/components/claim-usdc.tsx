"use client";

import type { Abi } from "viem";
import { useBlock, useConnection, useReadContract } from "wagmi";
import { chain, chainLabel, contracts } from "@/config/contracts";
import { mockUsdcFaucetAbi } from "@/generated/contracts";
import { useChainAction } from "@/hooks/use-chain-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import { claimWindow } from "@/lib/claim-eligibility";
import { claimStatus } from "@/lib/claim-status";
import { TransactionLink } from "@/components/transaction-link";
import { fitActionButtonClass } from "@/lib/control-class";
import { formatCountdown } from "@/lib/countdown";
import { claimFailedMessage, claimRevertedMessage } from "@/lib/faucet-errors";
import { formatUsdc } from "@/lib/format-usdc";

const chainContracts = contracts[chain.id];
const faucetAbi = mockUsdcFaucetAbi as Abi;

function describeError(error: unknown): string {
  return actionErrorMessage(error, [faucetAbi], claimFailedMessage);
}

function describeReceiptError(error: unknown): string {
  return actionReceiptErrorMessage(error, [faucetAbi], claimRevertedMessage);
}

export function ClaimUsdc() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const address = onChain ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const action = useChainAction({
    abi: mockUsdcFaucetAbi,
    account: address,
    address: chainContracts.mockUsdcFaucet,
    describeError,
    describeReceiptError,
    functionName: "claim",
    scope: identity,
  });
  const block = useBlock({
    chainId: chain.id,
    query: { enabled: onChain },
    watch: onChain,
  });
  const claimsToday = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: chainContracts.mockUsdcFaucet,
    chainId: chain.id,
    functionName: "claimsToday",
    query: { enabled: onChain },
  });
  const dailyClaimLimit = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: chainContracts.mockUsdcFaucet,
    functionName: "i_dailyClaimLimit",
    chainId: chain.id,
    query: { enabled: onChain },
  });
  const nextClaimArgs =
    address === undefined ? undefined : ([address] as const);
  const nextClaimAt = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: chainContracts.mockUsdcFaucet,
    args: nextClaimArgs,
    chainId: chain.id,
    functionName: "nextClaimAt",
    query: { enabled: address !== undefined },
  });
  const nextDailyReset = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: chainContracts.mockUsdcFaucet,
    chainId: chain.id,
    functionName: "nextDailyReset",
    query: { enabled: onChain },
  });
  const claimAmount = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: chainContracts.mockUsdcFaucet,
    functionName: "i_claimAmount",
    chainId: chain.id,
    query: { enabled: onChain },
  });

  const readsFailed =
    onChain &&
    (unread(claimsToday) ||
      unread(dailyClaimLimit) ||
      unread(nextClaimAt) ||
      unread(nextDailyReset) ||
      unread(claimAmount) ||
      (block.isError && block.data === undefined));
  const readsReady =
    block.data !== undefined &&
    claimsToday.data !== undefined &&
    dailyClaimLimit.data !== undefined &&
    nextClaimAt.data !== undefined &&
    nextDailyReset.data !== undefined &&
    claimAmount.data !== undefined;
  const eligibility = readsReady
    ? claimWindow({
        blockTimestamp: block.data.timestamp,
        nextClaimAt: nextClaimAt.data,
        claimsToday: claimsToday.data,
        dailyClaimLimit: dailyClaimLimit.data,
      })
    : undefined;
  const readsIncludeClaim =
    action.receipt.data !== undefined &&
    block.data !== undefined &&
    block.data.number >= action.receipt.data.blockNumber;
  const holdSuccess =
    action.isSuccess && eligibility?.status === "allowed" && !readsIncludeClaim;
  const canClaim =
    address !== undefined &&
    eligibility?.status === "allowed" &&
    !action.busy &&
    !holdSuccess;

  let countdown: string | undefined;
  let reason: string | undefined;
  if (eligibility !== undefined && !action.busy) {
    if (eligibility.status === "daily-cap") {
      reason = "Today's claim limit is full.";
    } else if (eligibility.status === "cooldown") {
      reason = "You can claim again when the cooldown ends.";
    }
  }
  if (
    !action.busy &&
    eligibility?.status === "daily-cap" &&
    nextDailyReset.data !== undefined &&
    block.data !== undefined
  ) {
    countdown = `Resets in ${formatCountdown(nextDailyReset.data, block.data.timestamp)}`;
  } else if (
    !action.busy &&
    eligibility?.status === "cooldown" &&
    nextClaimAt.data !== undefined &&
    block.data !== undefined
  ) {
    countdown = `Ready in ${formatCountdown(nextClaimAt.data, block.data.timestamp)}`;
  }
  const claimed =
    action.isSuccess &&
    claimAmount.data !== undefined &&
    (holdSuccess || eligibility?.status !== "allowed")
      ? `Claimed ${formatUsdc(claimAmount.data)} mUSDC.`
      : undefined;
  const status = claimStatus({
    claimed,
    confirming: action.confirming,
    connected: connection.isConnected,
    chainLabel,
    eligibility: eligibility?.status,
    onChain,
    readsFailed,
    readsReady,
    simulating: action.simulating,
    writePending: action.writePending,
  });

  return (
    <div className="flex h-full min-w-0 flex-col gap-3">
      {onChain && claimAmount.data !== undefined ? (
        <p className="text-sm text-ink tabular-nums">
          Claim amount: {formatUsdc(claimAmount.data)} mUSDC
        </p>
      ) : null}
      <button
        type="button"
        className={fitActionButtonClass()}
        disabled={!canClaim}
        onClick={() => {
          void action.send();
        }}
      >
        Claim mUSDC
      </button>
      {status ? <p className="text-sm text-ink-muted">{status}</p> : null}
      <TransactionLink hash={action.isSuccess ? action.hash : undefined} />
      {reason ? <p className="text-sm text-ink-muted">{reason}</p> : null}
      {countdown ? <p className="text-sm text-ink-muted tabular-nums">{countdown}</p> : null}
      {action.errorMessage ? <p role="alert">{action.errorMessage}</p> : null}
    </div>
  );
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}
