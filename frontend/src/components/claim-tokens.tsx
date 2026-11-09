"use client";

import { useBlock, useConnection, useReadContract } from "wagmi";
import { chain, chainLabel, contracts } from "@/config/contracts";
import { driverFaucetAbi, driverTokenAbi } from "@/generated/contracts";
import { useChainAction } from "@/hooks/use-chain-action";
import {
  claimEligibility,
  type ClaimEligibility,
} from "@/lib/claim-eligibility";
import { claimStatus } from "@/lib/claim-status";
import { FaucetPump } from "@/components/faucet-pump";
import { publishConfirmed, useFailureToast } from "@/components/toaster";
import { formatCountdown } from "@/lib/countdown";
import { ringPresentation } from "@/lib/ring";
import { faucetErrorMessage, receiptErrorMessage } from "@/lib/faucet-errors";
import { formatDvr } from "@/lib/format-dvr";

const chainContracts = contracts[chain.id];

export function ClaimTokens() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const address = onChain ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const action = useChainAction({
    abi: driverFaucetAbi,
    account: address,
    address: chainContracts.driverFaucet,
    describeError: faucetErrorMessage,
    describeReceiptError: receiptErrorMessage,
    functionName: "claim",
    scope: identity,
  });
  const block = useBlock({
    chainId: chain.id,
    query: { enabled: onChain },
    watch: onChain,
  });
  const claimsToday = useReadContract({
    abi: driverFaucetAbi,
    address: chainContracts.driverFaucet,
    chainId: chain.id,
    functionName: "claimsToday",
    query: { enabled: onChain },
  });
  const dailyClaimLimit = useReadContract({
    abi: driverFaucetAbi,
    address: chainContracts.driverFaucet,
    functionName: "i_dailyClaimLimit",
    chainId: chain.id,
    query: { enabled: onChain },
  });
  const nextClaimArgs =
    address === undefined ? undefined : ([address] as const);
  const nextClaimAt = useReadContract({
    abi: driverFaucetAbi,
    address: chainContracts.driverFaucet,
    args: nextClaimArgs,
    chainId: chain.id,
    functionName: "nextClaimAt",
    query: { enabled: address !== undefined },
  });
  const nextDailyReset = useReadContract({
    abi: driverFaucetAbi,
    address: chainContracts.driverFaucet,
    chainId: chain.id,
    functionName: "nextDailyReset",
    query: { enabled: onChain },
  });
  const claimAmount = useReadContract({
    abi: driverFaucetAbi,
    address: chainContracts.driverFaucet,
    functionName: "i_claimAmount",
    chainId: chain.id,
    query: { enabled: onChain },
  });
  const cooldown = useReadContract({
    abi: driverFaucetAbi,
    address: chainContracts.driverFaucet,
    functionName: "i_claimCooldown",
    chainId: chain.id,
    query: { enabled: onChain },
  });
  const faucetBalance = useReadContract({
    abi: driverTokenAbi,
    address: chainContracts.driverToken,
    args: [chainContracts.driverFaucet] as const,
    chainId: chain.id,
    functionName: "balanceOf",
    query: { enabled: onChain },
  });

  const readsFailed =
    onChain &&
    (unread(claimsToday) ||
      unread(dailyClaimLimit) ||
      unread(nextClaimAt) ||
      unread(nextDailyReset) ||
      unread(claimAmount) ||
      unread(cooldown) ||
      unread(faucetBalance) ||
      (block.isError && block.data === undefined));
  const readsReady =
    block.data !== undefined &&
    claimsToday.data !== undefined &&
    dailyClaimLimit.data !== undefined &&
    nextClaimAt.data !== undefined &&
    nextDailyReset.data !== undefined &&
    claimAmount.data !== undefined &&
    cooldown.data !== undefined &&
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
    chainLabel,
    eligibility: eligibility?.status,
    onChain,
    readsFailed,
    readsReady,
    simulating: action.simulating,
    writePending: action.writePending,
  });
  const remaining =
    block.data !== undefined && nextClaimAt.data !== undefined
      ? block.data.timestamp >= nextClaimAt.data
        ? 0n
        : nextClaimAt.data - block.data.timestamp
      : undefined;
  const ring =
    cooldown.data !== undefined && remaining !== undefined
      ? ringPresentation({
          dailyCap: eligibility?.status === "daily-cap",
          remaining,
          period: cooldown.data,
        })
      : undefined;
  useFailureToast(action.errorMessage);

  return (
    <FaucetPump
      title="DVR"
      bandClass="bg-[#1d4ed8]"
      amount={claimAmount.data !== undefined ? formatDvr(claimAmount.data) : undefined}
      unit="DVR"
      fraction={ring?.fraction}
      grey={ring?.grey ?? false}
      countdown={countdown}
      buttonLabel="Claim DVR"
      canClaim={canClaim}
      onClaim={() => {
        void action.send().then((claimedOk) => {
          if (claimedOk && claimAmount.data !== undefined) {
            publishConfirmed(`Claimed ${formatDvr(claimAmount.data)} DVR.`);
          }
        });
      }}
      status={status}
      hash={action.isSuccess ? action.hash : undefined}
      reason={reason}
      error={action.errorMessage}
      celebrate={claimed !== undefined}
    />
  );
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}
