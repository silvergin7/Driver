"use client";

import { useBlock, useConnection, useReadContract } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import { driverFaucetAbi, driverTokenAbi } from "@/generated/contracts";
import { useAnvilAction } from "@/hooks/use-anvil-action";
import {
  claimEligibility,
  type ClaimEligibility,
} from "@/lib/claim-eligibility";
import { claimStatus } from "@/lib/claim-status";
import { fitActionButtonClass } from "@/lib/control-class";
import { formatCountdown } from "@/lib/countdown";
import { faucetErrorMessage, receiptErrorMessage } from "@/lib/faucet-errors";
import { formatDvr } from "@/lib/format-dvr";

const anvilContracts = contracts[anvil.id];

export function ClaimTokens() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const address = onAnvil ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const action = useAnvilAction({
    abi: driverFaucetAbi,
    account: address,
    address: anvilContracts.driverFaucet,
    describeError: faucetErrorMessage,
    describeReceiptError: receiptErrorMessage,
    functionName: "claim",
    scope: identity,
  });
  const block = useBlock({
    chainId: anvil.id,
    query: { enabled: onAnvil },
    watch: onAnvil,
  });
  const claimsToday = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    chainId: anvil.id,
    functionName: "claimsToday",
    query: { enabled: onAnvil },
  });
  const dailyClaimLimit = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    functionName: "i_dailyClaimLimit",
    chainId: anvil.id,
    query: { enabled: onAnvil },
  });
  const nextClaimArgs =
    address === undefined ? undefined : ([address] as const);
  const nextClaimAt = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    args: nextClaimArgs,
    chainId: anvil.id,
    functionName: "nextClaimAt",
    query: { enabled: address !== undefined },
  });
  const nextDailyReset = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    chainId: anvil.id,
    functionName: "nextDailyReset",
    query: { enabled: onAnvil },
  });
  const claimAmount = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    functionName: "i_claimAmount",
    chainId: anvil.id,
    query: { enabled: onAnvil },
  });
  const faucetBalance = useReadContract({
    abi: driverTokenAbi,
    address: anvilContracts.driverToken,
    args: [anvilContracts.driverFaucet] as const,
    chainId: anvil.id,
    functionName: "balanceOf",
    query: { enabled: onAnvil },
  });

  const readsFailed =
    onAnvil &&
    (unread(claimsToday) ||
      unread(dailyClaimLimit) ||
      unread(nextClaimAt) ||
      unread(nextDailyReset) ||
      unread(claimAmount) ||
      unread(faucetBalance) ||
      (block.isError && block.data === undefined));
  const readsReady =
    block.data !== undefined &&
    claimsToday.data !== undefined &&
    dailyClaimLimit.data !== undefined &&
    nextClaimAt.data !== undefined &&
    nextDailyReset.data !== undefined &&
    claimAmount.data !== undefined &&
    faucetBalance.data !== undefined;
  const eligibility: ClaimEligibility | undefined = readsReady
    ? claimEligibility({
        blockTimestamp: block.data.timestamp,
        nextClaimAt: nextClaimAt.data,
        claimsToday: claimsToday.data,
        dailyClaimLimit: dailyClaimLimit.data,
        faucetBalance: faucetBalance.data,
        claimAmount: claimAmount.data,
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
    } else if (eligibility.status === "faucet-empty") {
      reason = "The faucet does not have enough DVR for a claim.";
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
      ? `Claimed ${formatDvr(claimAmount.data)} DVR.`
      : undefined;
  const status = claimStatus({
    claimed,
    confirming: action.confirming,
    connected: connection.isConnected,
    eligibility: eligibility?.status,
    onAnvil,
    readsFailed,
    readsReady,
    simulating: action.simulating,
    writePending: action.writePending,
  });

  return (
    <div className="flex h-full min-w-0 flex-col gap-3">
      {onAnvil && claimAmount.data !== undefined ? (
        <p className="text-sm text-ink tabular-nums">
          Claim amount: {formatDvr(claimAmount.data)} DVR
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
        Claim Tokens
      </button>
      {status ? <p className="text-sm text-ink-muted">{status}</p> : null}
      {reason ? <p className="text-sm text-ink-muted">{reason}</p> : null}
      {countdown ? <p className="text-sm text-ink-muted tabular-nums">{countdown}</p> : null}
      {action.errorMessage ? <p role="alert">{action.errorMessage}</p> : null}
    </div>
  );
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}
