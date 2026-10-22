"use client";

import { useState } from "react";
import type { Abi, Address } from "viem";
import { zeroAddress } from "viem";
import { useConnection, useReadContract } from "wagmi";
import { chain, chainLabel, contracts } from "@/config/contracts";
import { switchPrompt } from "@/lib/switch-prompt";
import {
  degenDriverAbi,
  demoDriverClockAbi,
  driverTokenAbi,
  driverVoteAbi,
  mockFarmAbi,
  roundScheduleAbi,
} from "@/generated/contracts";
import { useChainAction } from "@/hooks/use-chain-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import {
  actionButtonClass,
  inputClass,
} from "@/lib/control-class";
import { Card } from "@/components/ui/card";
import { StatList } from "@/components/ui/stat-list";
import { farmLabel } from "@/lib/farm-label";
import { formatBps } from "@/lib/format-bps";
import { formatDvr } from "@/lib/format-dvr";
import { formatCountdown } from "@/lib/countdown";
import { parseTokenAmount, type ParsedAmount } from "@/lib/parse-amount";
import { roundChoice } from "@/lib/round-choice";

const chainContracts = contracts[chain.id];
const voteAbi = driverVoteAbi as Abi;
const tokenAbi = driverTokenAbi as Abi;
const failed = "The transaction failed.";
const reverted = "The transaction reverted.";

function describeError(error: unknown): string {
  return actionErrorMessage(error, [voteAbi, tokenAbi], failed);
}

function describeReceiptError(error: unknown): string {
  return actionReceiptErrorMessage(error, [voteAbi, tokenAbi], reverted);
}

function useListedFarm(
  index: number,
  count: bigint | undefined,
  onChain: boolean,
) {
  const listed = onChain && count !== undefined && count > BigInt(index);
  const strategy = useReadContract({
    abi: degenDriverAbi,
    address: chainContracts.degenDriver,
    args: [BigInt(index)] as const,
    chainId: chain.id,
    functionName: "strategyAt",
    query: { enabled: listed },
  });
  const farm = listed ? strategy.data : undefined;
  const apr = useReadContract({
    abi: mockFarmAbi,
    address: farm ?? zeroAddress,
    chainId: chain.id,
    functionName: "aprBps",
    query: { enabled: farm !== undefined },
  });
  const tally = useReadContract({
    abi: driverVoteAbi,
    address: chainContracts.driverVote,
    args: [farm ?? zeroAddress] as const,
    chainId: chain.id,
    functionName: "openTally",
    query: { enabled: farm !== undefined },
  });
  return { strategy, apr, tally, farm };
}

export function LockVote() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const address = onChain ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const [lockText, setLockText] = useState("");
  const [unlockText, setUnlockText] = useState("");
  const [selected, setSelected] = useState<Address>();
  const [notice, setNotice] = useState<string>();
  const [noticeScope, setNoticeScope] = useState(identity);
  const [lastAction, setLastAction] = useState<"lock" | "unlock" | "vote">();
  if (noticeScope !== identity) {
    setNoticeScope(identity);
    setNotice(undefined);
    setLastAction(undefined);
  }

  const accountArgs = address === undefined ? undefined : ([address] as const);

  const balanceParameters = {
    abi: driverTokenAbi,
    address: chainContracts.driverToken,
    args: accountArgs,
    chainId: chain.id,
    functionName: "balanceOf",
  } as const;
  const balance = useReadContract({
    ...balanceParameters,
    query: {
      enabled: address !== undefined,
    },
  });
  const allowanceParameters = {
    abi: driverTokenAbi,
    address: chainContracts.driverToken,
    args:
      address === undefined
        ? undefined
        : ([address, chainContracts.driverVote] as const),
    chainId: chain.id,
    functionName: "allowance",
  } as const;
  const allowance = useReadContract({
    ...allowanceParameters,
    query: {
      enabled: address !== undefined,
    },
  });
  const lockedParameters = {
    abi: driverVoteAbi,
    address: chainContracts.driverVote,
    args: accountArgs,
    chainId: chain.id,
    functionName: "locked",
  } as const;
  const locked = useReadContract({
    ...lockedParameters,
    query: {
      enabled: address !== undefined,
    },
  });
  const unlockParameters = {
    abi: driverVoteAbi,
    address: chainContracts.driverVote,
    args: accountArgs,
    chainId: chain.id,
    functionName: "unlockStatus",
  } as const;
  const unlockState = useReadContract({
    ...unlockParameters,
    query: {
      enabled: address !== undefined,
    },
  });
  const roundParameters = {
    abi: roundScheduleAbi,
    address: chainContracts.roundSchedule,
    chainId: chain.id,
    functionName: "currentRound",
  } as const;
  const round = useReadContract({
    ...roundParameters,
    query: {
      enabled: onChain,
    },
  });
  const clockParameters = {
    abi: demoDriverClockAbi,
    address: chainContracts.demoDriverClock,
    chainId: chain.id,
    functionName: "currentTime",
  } as const;
  const clock = useReadContract({
    ...clockParameters,
    query: {
      enabled: onChain,
    },
  });
  const countParameters = {
    abi: degenDriverAbi,
    address: chainContracts.degenDriver,
    chainId: chain.id,
    functionName: "strategyCount",
  } as const;
  const strategyCount = useReadContract({
    ...countParameters,
    query: {
      enabled: onChain,
    },
  });
  const voteParameters = {
    abi: driverVoteAbi,
    address: chainContracts.driverVote,
    args:
      address === undefined || round.data === undefined
        ? undefined
        : ([round.data, address] as const),
    chainId: chain.id,
    functionName: "voteOf",
  } as const;
  const voteOf = useReadContract({
    ...voteParameters,
    query: {
      enabled: address !== undefined && round.data !== undefined,
    },
  });
  const openLeaderParameters = {
    abi: driverVoteAbi,
    address: chainContracts.driverVote,
    args: [round.data ?? 0n] as const,
    chainId: chain.id,
    functionName: "leader",
  } as const;
  const openLeader = useReadContract({
    ...openLeaderParameters,
    query: {
      enabled: onChain && round.data !== undefined,
    },
  });
  const closedRound = round.data !== undefined && round.data > 0n ? round.data - 1n : 0n;
  const closedLeaderParameters = {
    abi: driverVoteAbi,
    address: chainContracts.driverVote,
    args: [closedRound] as const,
    chainId: chain.id,
    functionName: "leader",
  } as const;
  const closedLeader = useReadContract({
    ...closedLeaderParameters,
    query: {
      enabled: onChain && round.data !== undefined && round.data > 0n,
    },
  });

  const farm0 = useListedFarm(0, strategyCount.data, onChain);
  const farm1 = useListedFarm(1, strategyCount.data, onChain);
  const farm2 = useListedFarm(2, strategyCount.data, onChain);
  const listed = [farm0, farm1, farm2].filter(
    (farm) => farm.farm !== undefined,
  );
  const countTooLong =
    strategyCount.data !== undefined && strategyCount.data > 3n;

  const lockParsed = parseTokenAmount(lockText, 18);
  const unlockParsed = parseTokenAmount(unlockText, 18);
  const lockAmount = lockParsed.status === "amount" ? lockParsed.amount : 0n;
  const unlockAmount =
    unlockParsed.status === "amount" ? unlockParsed.amount : 0n;
  const voteFarm = selected ?? listed[0]?.farm ?? zeroAddress;

  const approve = useChainAction({
    abi: driverTokenAbi,
    account: address,
    address: chainContracts.driverToken,
    args: [chainContracts.driverVote, lockAmount] as const,
    describeError,
    describeReceiptError,
    functionName: "approve",
    scope: identity,
  });
  const lock = useChainAction({
    abi: driverVoteAbi,
    account: address,
    address: chainContracts.driverVote,
    args: [lockAmount] as const,
    describeError,
    describeReceiptError,
    functionName: "lock",
    scope: identity,
  });
  const unlock = useChainAction({
    abi: driverVoteAbi,
    account: address,
    address: chainContracts.driverVote,
    args: [unlockAmount] as const,
    describeError,
    describeReceiptError,
    functionName: "unlock",
    scope: identity,
  });
  const vote = useChainAction({
    abi: driverVoteAbi,
    account: address,
    address: chainContracts.driverVote,
    args: [voteFarm] as const,
    describeError,
    describeReceiptError,
    functionName: "vote",
    scope: identity,
  });

  const busy = approve.busy || lock.busy || unlock.busy || vote.busy;
  const accountReady =
    address !== undefined &&
    balance.data !== undefined &&
    allowance.data !== undefined &&
    locked.data !== undefined &&
    unlockState.data !== undefined &&
    clock.data !== undefined;
  const farmsReady =
    strategyCount.data !== undefined &&
    !countTooLong &&
    listed.length === Number(strategyCount.data) &&
    listed.every(
      (farm) => farm.apr.data !== undefined && farm.tally.data !== undefined,
    ) &&
    round.data !== undefined &&
    voteOf.data !== undefined &&
    openLeader.data !== undefined &&
    (round.data === 0n || closedLeader.data !== undefined);
  const readsFailed =
    onChain &&
    (unread(balance) ||
      unread(allowance) ||
      unread(locked) ||
      unread(unlockState) ||
      unread(clock) ||
      unread(round) ||
      unread(strategyCount) ||
      unread(voteOf) ||
      unread(openLeader) ||
      unread(closedLeader) ||
      listed.some(
        (farm) =>
          unread(farm.strategy) || unread(farm.apr) || unread(farm.tally),
      ));
  const labels = new Map<Address, string>();
  for (const farm of listed) {
    if (farm.farm !== undefined && farm.apr.data !== undefined) {
      labels.set(farm.farm, farmLabel(farm.apr.data, farm.farm));
    }
  }
  const choice = (leader: Address | undefined) =>
    leader === undefined ? undefined : roundChoice(leader);
  const openChoice = choice(openLeader.data);
  const closedChoice =
    round.data !== undefined && round.data > 0n
      ? choice(closedLeader.data)
      : undefined;
  const currentVote =
    voteOf.data !== undefined && voteOf.data !== zeroAddress
      ? voteOf.data
      : undefined;

  const lockReason = amountReason(lockParsed, balance.data, "wallet");
  const unlockReason = unlockBlockReason(
    unlockParsed,
    locked.data,
    unlockState.data,
  );
  const voteReason = voteBlockReason(
    locked.data,
    selected,
    currentVote,
    countTooLong,
  );
  const canLock =
    accountReady && lockParsed.status === "amount" && lockReason === undefined && !busy;
  const canUnlock =
    accountReady &&
    unlockParsed.status === "amount" &&
    unlockReason === undefined &&
    unlockState.data?.[0] === true &&
    !busy;
  const canVote =
    accountReady &&
    farmsReady &&
    selected !== undefined &&
    voteReason === undefined &&
    !busy;

  async function onLock(): Promise<void> {
    if (lockParsed.status !== "amount" || allowance.data === undefined) {
      return;
    }
    setLastAction("lock");
    setNotice(undefined);
    if (allowance.data < lockParsed.amount) {
      const approved = await approve.send();
      if (!approved) {
        return;
      }
    }
    const lockedOk = await lock.send();
    if (lockedOk) {
      setNotice(`Locked ${formatDvr(lockParsed.amount)} DVR.`);
    }
  }

  async function onUnlock(): Promise<void> {
    if (unlockParsed.status !== "amount") {
      return;
    }
    setLastAction("unlock");
    setNotice(undefined);
    const unlocked = await unlock.send();
    if (unlocked) {
      setNotice(`Unlocked ${formatDvr(unlockParsed.amount)} DVR.`);
    }
  }

  async function onVote(): Promise<void> {
    if (selected === undefined) {
      return;
    }
    setLastAction("vote");
    setNotice(undefined);
    const voted = await vote.send();
    if (voted) {
      setNotice(`Voted for ${labels.get(selected) ?? selected}.`);
    }
  }

  const errorMessage =
    lastAction === "lock"
      ? (approve.errorMessage ?? lock.errorMessage)
      : lastAction === "unlock"
        ? unlock.errorMessage
        : lastAction === "vote"
          ? vote.errorMessage
          : undefined;
  let status: string | undefined;
  if (!connection.isConnected) {
    status = "Connect a wallet to lock and vote.";
  } else if (!onChain) {
    status = switchPrompt(chainLabel, "to lock and vote.");
  } else if (readsFailed || countTooLong) {
    status = countTooLong
      ? "The farm list is longer than this page can show."
      : "Lock and vote status unavailable.";
  } else if (!accountReady || !farmsReady) {
    status = "Loading lock and vote…";
  } else if (approve.simulating) {
    status = "Checking the approval.";
  } else if (approve.writePending || lock.writePending || unlock.writePending || vote.writePending) {
    status = "Waiting for the wallet.";
  } else if (approve.confirming) {
    status = "Confirming the approval.";
  } else if (lock.simulating) {
    status = "Checking the lock.";
  } else if (lock.confirming) {
    status = "Confirming the lock.";
  } else if (unlock.simulating) {
    status = "Checking the unlock.";
  } else if (unlock.confirming) {
    status = "Confirming the unlock.";
  } else if (vote.simulating) {
    status = "Checking the vote.";
  } else if (vote.confirming) {
    status = "Confirming the vote.";
  } else if (notice) {
    status = notice;
  }

  const unlockCountdown =
    !busy &&
    accountReady &&
    unlockState.data?.[0] === false &&
    unlockState.data[1] > 0n &&
    clock.data !== undefined
      ? `Unlocks in ${formatCountdown(unlockState.data[1], clock.data)}`
      : undefined;

  if (connection.isConnected && !onChain) {
    return (
      <Card
        className="w-full"
        title="Lock and vote"
        subtitle="Instructors vote on Degen Driver's speed."
      >
        <p className="text-sm text-ink-muted">
          {switchPrompt(chainLabel, "to lock and vote.")}
        </p>
      </Card>
    );
  }

  const lockedRow = accountReady
    ? [{ label: "Locked", value: `${formatDvr(locked.data ?? 0n)} DVR` }]
    : [];
  const voteRows = [
    farmsReady
      ? {
          label: "Open round leader",
          value:
            openChoice === undefined
              ? "No votes yet."
              : (labels.get(openChoice) ?? openChoice),
        }
      : undefined,
    farmsReady && round.data !== undefined && round.data > 0n
      ? {
          label: `Round ${closedRound.toString()} choice`,
          value:
            closedChoice === undefined
              ? "No votes."
              : (labels.get(closedChoice) ?? closedChoice),
        }
      : undefined,
    currentVote !== undefined
      ? { label: "Your vote", value: labels.get(currentVote) ?? currentVote }
      : undefined,
  ].filter((row): row is { label: string; value: string } => row !== undefined);

  return (
    <Card
      className="w-full"
      title="Lock and vote"
      subtitle="Instructors vote on Degen Driver's speed."
    >
      <div className="flex flex-col gap-6 md:grid md:grid-cols-2 md:items-start">
        <div className="flex min-w-0 flex-col gap-4">
          <div className="flex items-end gap-2">
            <label className="flex min-w-0 flex-1 flex-col gap-1 text-sm text-ink-muted">
              Lock amount
              <input
                className={`${inputClass()} w-full`}
                inputMode="decimal"
                value={lockText}
                onChange={(event) => {
                  setLockText(event.target.value);
                }}
              />
            </label>
            <button
              type="button"
              className={`${actionButtonClass()} shrink-0 whitespace-nowrap`}
              disabled={!canLock}
              onClick={() => {
                void onLock();
              }}
            >
              Lock DVR
            </button>
          </div>
          <div className="flex items-end gap-2">
            <label className="flex min-w-0 flex-1 flex-col gap-1 text-sm text-ink-muted">
              Unlock amount
              <input
                className={`${inputClass()} w-full`}
                inputMode="decimal"
                value={unlockText}
                onChange={(event) => {
                  setUnlockText(event.target.value);
                }}
              />
            </label>
            <button
              type="button"
              className={`${actionButtonClass()} shrink-0 whitespace-nowrap`}
              disabled={!canUnlock}
              onClick={() => {
                void onUnlock();
              }}
            >
              Unlock DVR
            </button>
          </div>
          {lockedRow.length > 0 ? <StatList rows={lockedRow} /> : null}
        </div>
        <div className="flex min-w-0 flex-col gap-4">
          {voteRows.length > 0 ? <StatList rows={voteRows} /> : null}
          <div className="grid grid-cols-2 gap-3 lg:flex">
            {listed.map((farm) =>
              farm.farm === undefined ||
              farm.apr.data === undefined ||
              farm.tally.data === undefined ? null : (
                <label
                  key={farm.farm}
                  className="flex min-w-0 items-start gap-2 text-sm text-ink lg:flex-1"
                >
                  <input
                    type="radio"
                    name="farm"
                    className="mt-1"
                    checked={selected === farm.farm}
                    onChange={() => {
                      setSelected(farm.farm);
                    }}
                  />
                  <span className="min-w-0 flex-1">
                    {labels.get(farm.farm) ?? farm.farm} ({formatBps(farm.apr.data)} APR)
                  </span>
                  <span className="shrink-0 tabular-nums">
                    {formatDvr(farm.tally.data)} DVR
                  </span>
                </label>
              ),
            )}
          </div>
          <button
            type="button"
            className={`${actionButtonClass()} w-fit`}
            disabled={!canVote}
            onClick={() => {
              void onVote();
            }}
          >
            Vote
          </button>
        </div>
      </div>
      {status ? <p className="text-sm text-ink-muted">{status}</p> : null}
      {lockReason && !busy ? <p className="text-sm text-ink-muted">{lockReason}</p> : null}
      {unlockReason && !busy ? <p className="text-sm text-ink-muted">{unlockReason}</p> : null}
      {voteReason && !busy ? <p className="text-sm text-ink-muted">{voteReason}</p> : null}
      {unlockCountdown ? (
        <p className="text-sm text-ink-muted tabular-nums">{unlockCountdown}</p>
      ) : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
    </Card>
  );
}

function amountReason(
  parsed: ParsedAmount,
  balance: bigint | undefined,
  source: "wallet" | "lock",
): string | undefined {
  if (parsed.status === "empty") {
    return undefined;
  }
  if (parsed.status === "invalid") {
    return "Enter a DVR amount.";
  }
  if (parsed.status === "zero") {
    return "Enter an amount above zero.";
  }
  if (balance !== undefined && parsed.amount > balance) {
    return source === "wallet"
      ? "That is more DVR than the wallet holds."
      : "That is more DVR than the lock.";
  }
  return undefined;
}

function unlockBlockReason(
  parsed: ParsedAmount,
  lockedBalance: bigint | undefined,
  status: readonly [boolean, bigint] | undefined,
): string | undefined {
  const amount = amountReason(parsed, lockedBalance, "lock");
  if (amount !== undefined) {
    return amount;
  }
  if (parsed.status === "empty") {
    return undefined;
  }
  if (lockedBalance === 0n) {
    return "Nothing is locked.";
  }
  if (status?.[0] === false) {
    return "Unlock waits until this round ends.";
  }
  return undefined;
}

function voteBlockReason(
  lockedBalance: bigint | undefined,
  selected: Address | undefined,
  currentVote: Address | undefined,
  countTooLong: boolean,
): string | undefined {
  if (countTooLong) {
    return "The farm list is longer than this page can show.";
  }
  if (lockedBalance === 0n) {
    return "Lock DVR before voting.";
  }
  if (selected !== undefined && selected === currentVote) {
    return "That farm already has your vote.";
  }
  return undefined;
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}
