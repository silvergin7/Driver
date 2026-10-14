"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import type { Hex } from "viem";
import {
  useBlock,
  useConfig,
  useConnection,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { simulateContract } from "wagmi/actions";
import { anvil, contracts } from "@/config/contracts";
import { driverFaucetAbi, driverTokenAbi } from "@/generated/contracts";
import { claimEligibility, type ClaimEligibility } from "@/lib/claim-eligibility";
import { claimStatus } from "@/lib/claim-status";
import { formatCountdown } from "@/lib/countdown";
import { faucetErrorMessage, receiptErrorMessage } from "@/lib/faucet-errors";
import { formatDvr } from "@/lib/format-dvr";

const anvilContracts = contracts[anvil.id];

export function ClaimTokens() {
  const connection = useConnection();
  const config = useConfig();
  const queryClient = useQueryClient();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const address = onAnvil ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const [scope, setScope] = useState(identity);
  const [simulating, setSimulating] = useState(false);
  const [simulationError, setSimulationError] = useState<string>();
  const identityRef = useRef(identity);
  const refreshedHash = useRef<Hex | undefined>(undefined);
  const {
    mutate,
    isPending: writePending,
    data: hash,
    error: writeError,
    reset,
  } = useWriteContract();

  if (scope !== identity) {
    setScope(identity);
    setSimulating(false);
    setSimulationError(undefined);
    reset();
  }

  useEffect(() => {
    identityRef.current = identity;
  }, [identity]);

  const block = useBlock({
    chainId: anvil.id,
    query: { enabled: onAnvil },
    watch: onAnvil,
  });
  const claimsToday = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    functionName: "claimsToday",
    chainId: anvil.id,
    blockNumber: block.data?.number,
    query: { enabled: onAnvil },
  });
  const dailyClaimLimit = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    functionName: "i_dailyClaimLimit",
    chainId: anvil.id,
    query: { enabled: onAnvil },
  });
  const nextClaimAt = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    functionName: "nextClaimAt",
    args: address === undefined ? undefined : [address],
    chainId: anvil.id,
    blockNumber: block.data?.number,
    query: { enabled: address !== undefined },
  });
  const nextDailyReset = useReadContract({
    abi: driverFaucetAbi,
    address: anvilContracts.driverFaucet,
    functionName: "nextDailyReset",
    chainId: anvil.id,
    blockNumber: block.data?.number,
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
    functionName: "balanceOf",
    args: [anvilContracts.driverFaucet],
    chainId: anvil.id,
    blockNumber: block.data?.number,
    query: { enabled: onAnvil },
  });
  const receipt = useWaitForTransactionReceipt({
    chainId: anvil.id,
    hash,
  });

  useEffect(() => {
    if (!receipt.isSuccess || hash === undefined || refreshedHash.current === hash) {
      return;
    }
    refreshedHash.current = hash;
    void queryClient.invalidateQueries({ queryKey: ["readContract"] });
  }, [hash, queryClient, receipt.isSuccess]);

  const readsFailed =
    onAnvil &&
    (claimsToday.isError ||
      dailyClaimLimit.isError ||
      nextClaimAt.isError ||
      nextDailyReset.isError ||
      claimAmount.isError ||
      faucetBalance.isError ||
      block.isError);
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
  const confirming =
    hash !== undefined && !receipt.isSuccess && !receipt.isError;
  const busy = simulating || writePending || confirming;
  const readsIncludeClaim =
    receipt.data !== undefined &&
    block.data !== undefined &&
    block.data.number >= receipt.data.blockNumber;
  const holdSuccess =
    receipt.isSuccess && eligibility?.status === "allowed" && !readsIncludeClaim;
  const canClaim =
    address !== undefined &&
    eligibility?.status === "allowed" &&
    !busy &&
    !holdSuccess;

  async function onClaim(): Promise<void> {
    if (address === undefined) {
      return;
    }
    const started = identityRef.current;
    reset();
    setSimulationError(undefined);
    setSimulating(true);
    try {
      await simulateContract(config, {
        abi: driverFaucetAbi,
        account: address,
        address: anvilContracts.driverFaucet,
        chainId: anvil.id,
        functionName: "claim",
      });
    } catch (error) {
      if (identityRef.current === started) {
        setSimulationError(faucetErrorMessage(error));
        setSimulating(false);
      }
      return;
    }
    if (identityRef.current !== started) {
      return;
    }
    setSimulating(false);
    mutate({
      abi: driverFaucetAbi,
      account: address,
      address: anvilContracts.driverFaucet,
      chainId: anvil.id,
      functionName: "claim",
    });
  }

  const errorMessage =
    hash !== undefined && receipt.isError
      ? receiptErrorMessage(receipt.error)
      : writeError
        ? faucetErrorMessage(writeError)
        : simulationError;
  let countdown: string | undefined;
  let reason: string | undefined;
  if (eligibility !== undefined && !busy) {
    if (eligibility.status === "daily-cap") {
      reason = "Today's claim limit is full.";
    } else if (eligibility.status === "cooldown") {
      reason = "You can claim again when the cooldown ends.";
    } else if (eligibility.status === "faucet-empty") {
      reason = "The faucet does not have enough DVR for a claim.";
    }
  }
  if (
    !busy &&
    eligibility?.status === "daily-cap" &&
    nextDailyReset.data !== undefined &&
    block.data !== undefined
  ) {
    countdown = `Resets in ${formatCountdown(nextDailyReset.data, block.data.timestamp)}`;
  } else if (
    !busy &&
    eligibility?.status === "cooldown" &&
    nextClaimAt.data !== undefined &&
    block.data !== undefined
  ) {
    countdown = `Ready in ${formatCountdown(nextClaimAt.data, block.data.timestamp)}`;
  }
  const claimed =
    receipt.isSuccess &&
    claimAmount.data !== undefined &&
    (holdSuccess || eligibility?.status !== "allowed")
      ? `Claimed ${formatDvr(claimAmount.data)} DVR.`
      : undefined;
  const status = claimStatus({
    claimed,
    confirming,
    connected: connection.isConnected,
    eligibility: eligibility?.status,
    onAnvil,
    readsFailed,
    readsReady,
    simulating,
    writePending,
  });

  return (
    <section className="flex w-full flex-col gap-3 text-left">
      {onAnvil && claimAmount.data !== undefined ? (
        <p>Claim amount: {formatDvr(claimAmount.data)} DVR</p>
      ) : null}
      <button
        type="button"
        className="w-fit rounded-md border px-3 py-2 disabled:opacity-50"
        disabled={!canClaim}
        onClick={() => {
          void onClaim();
        }}
      >
        Claim Tokens
      </button>
      {status ? <p>{status}</p> : null}
      {reason ? <p>{reason}</p> : null}
      {countdown ? <p>{countdown}</p> : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
    </section>
  );
}
