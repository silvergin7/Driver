"use client";

import type { Abi } from "viem";
import { useBlock, useConnection, useReadContract } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import { mockUsdcFaucetAbi } from "@/generated/contracts";
import { useAnvilAction } from "@/hooks/use-anvil-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import { claimWindow } from "@/lib/claim-eligibility";
import { claimStatus } from "@/lib/claim-status";
import { formatCountdown } from "@/lib/countdown";
import { claimFailedMessage, claimRevertedMessage } from "@/lib/faucet-errors";
import { formatUsdc } from "@/lib/format-usdc";

const anvilContracts = contracts[anvil.id];
const faucetAbi = mockUsdcFaucetAbi as Abi;

function describeError(error: unknown): string {
  return actionErrorMessage(error, [faucetAbi], claimFailedMessage);
}

function describeReceiptError(error: unknown): string {
  return actionReceiptErrorMessage(error, [faucetAbi], claimRevertedMessage);
}

export function ClaimUsdc() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const address = onAnvil ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const action = useAnvilAction({
    abi: mockUsdcFaucetAbi,
    account: address,
    address: anvilContracts.mockUsdcFaucet,
    describeError,
    describeReceiptError,
    functionName: "claim",
    scope: identity,
  });
  const block = useBlock({
    chainId: anvil.id,
    query: { enabled: onAnvil },
    watch: onAnvil,
  });
  const claimsToday = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: anvilContracts.mockUsdcFaucet,
    chainId: anvil.id,
    functionName: "claimsToday",
    query: { enabled: onAnvil },
  });
  const dailyClaimLimit = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: anvilContracts.mockUsdcFaucet,
    functionName: "i_dailyClaimLimit",
    chainId: anvil.id,
    query: { enabled: onAnvil },
  });
  const nextClaimArgs =
    address === undefined ? undefined : ([address] as const);
  const nextClaimAt = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: anvilContracts.mockUsdcFaucet,
    args: nextClaimArgs,
    chainId: anvil.id,
    functionName: "nextClaimAt",
    query: { enabled: address !== undefined },
  });
  const nextDailyReset = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: anvilContracts.mockUsdcFaucet,
    chainId: anvil.id,
    functionName: "nextDailyReset",
    query: { enabled: onAnvil },
  });
  const claimAmount = useReadContract({
    abi: mockUsdcFaucetAbi,
    address: anvilContracts.mockUsdcFaucet,
    functionName: "i_claimAmount",
    chainId: anvil.id,
    query: { enabled: onAnvil },
  });

  const readsFailed =
    onAnvil &&
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
    eligibility: eligibility?.status,
    onAnvil,
    readsFailed,
    readsReady,
    simulating: action.simulating,
    writePending: action.writePending,
  });

  return (
    <section className="flex w-full flex-col gap-3 text-left">
      {onAnvil && claimAmount.data !== undefined ? (
        <p className="tabular-nums">
          Claim amount: {formatUsdc(claimAmount.data)} mUSDC
        </p>
      ) : null}
      <button
        type="button"
        className="w-fit rounded-md border px-3 py-2 disabled:opacity-50"
        disabled={!canClaim}
        onClick={() => {
          void action.send();
        }}
      >
        Claim mUSDC
      </button>
      {status ? <p>{status}</p> : null}
      {reason ? <p>{reason}</p> : null}
      {countdown ? <p className="tabular-nums">{countdown}</p> : null}
      {action.errorMessage ? <p role="alert">{action.errorMessage}</p> : null}
    </section>
  );
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}
