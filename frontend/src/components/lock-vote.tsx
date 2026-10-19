"use client";

import { useState } from "react";
import type { Abi, Address } from "viem";
import { zeroAddress } from "viem";
import { useConnection, useReadContract } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import {
  degenDriverAbi,
  demoDriverClockAbi,
  driverTokenAbi,
  driverVoteAbi,
  mockFarmAbi,
  roundScheduleAbi,
} from "@/generated/contracts";
import { useAnvilAction } from "@/hooks/use-anvil-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import {
  actionButtonClass,
  headingClass,
  inputClass,
  sectionClass,
} from "@/lib/control-class";
import { farmLabel } from "@/lib/farm-label";
import { formatDvr } from "@/lib/format-dvr";
import { formatCountdown } from "@/lib/countdown";
import { parseTokenAmount, type ParsedAmount } from "@/lib/parse-amount";
import { roundChoice } from "@/lib/round-choice";

const anvilContracts = contracts[anvil.id];
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
  onAnvil: boolean,
) {
  const listed = onAnvil && count !== undefined && count > BigInt(index);
  const strategy = useReadContract({
    abi: degenDriverAbi,
    address: anvilContracts.degenDriver,
    args: [BigInt(index)] as const,
    chainId: anvil.id,
    functionName: "strategyAt",
    query: { enabled: listed },
  });
  const farm = listed ? strategy.data : undefined;
  const apr = useReadContract({
    abi: mockFarmAbi,
    address: farm ?? zeroAddress,
    chainId: anvil.id,
    functionName: "aprBps",
    query: { enabled: farm !== undefined },
  });
  const tally = useReadContract({
    abi: driverVoteAbi,
    address: anvilContracts.driverVote,
    args: [farm ?? zeroAddress] as const,
    chainId: anvil.id,
    functionName: "openTally",
    query: { enabled: farm !== undefined },
  });
  return { strategy, apr, tally, farm };
}

export function LockVote() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const address = onAnvil ? connection.address : undefined;
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
    address: anvilContracts.driverToken,
    args: accountArgs,
    chainId: anvil.id,
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
    address: anvilContracts.driverToken,
    args:
      address === undefined
        ? undefined
        : ([address, anvilContracts.driverVote] as const),
    chainId: anvil.id,
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
    address: anvilContracts.driverVote,
    args: accountArgs,
    chainId: anvil.id,
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
    address: anvilContracts.driverVote,
    args: accountArgs,
    chainId: anvil.id,
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
    address: anvilContracts.roundSchedule,
    chainId: anvil.id,
    functionName: "currentRound",
  } as const;
  const round = useReadContract({
    ...roundParameters,
    query: {
      enabled: onAnvil,
    },
  });
  const clockParameters = {
    abi: demoDriverClockAbi,
    address: anvilContracts.demoDriverClock,
    chainId: anvil.id,
    functionName: "currentTime",
  } as const;
  const clock = useReadContract({
    ...clockParameters,
    query: {
      enabled: onAnvil,
    },
  });
  const countParameters = {
    abi: degenDriverAbi,
    address: anvilContracts.degenDriver,
    chainId: anvil.id,
    functionName: "strategyCount",
  } as const;
  const strategyCount = useReadContract({
    ...countParameters,
    query: {
      enabled: onAnvil,
    },
  });
  const voteParameters = {
    abi: driverVoteAbi,
    address: anvilContracts.driverVote,
    args:
      address === undefined || round.data === undefined
        ? undefined
        : ([round.data, address] as const),
    chainId: anvil.id,
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
    address: anvilContracts.driverVote,
    args: [round.data ?? 0n] as const,
    chainId: anvil.id,
    functionName: "leader",
  } as const;
  const openLeader = useReadContract({
    ...openLeaderParameters,
    query: {
      enabled: onAnvil && round.data !== undefined,
    },
  });
  const closedRound = round.data !== undefined && round.data > 0n ? round.data - 1n : 0n;
  const closedLeaderParameters = {
    abi: driverVoteAbi,
    address: anvilContracts.driverVote,
    args: [closedRound] as const,
    chainId: anvil.id,
    functionName: "leader",
  } as const;
  const closedLeader = useReadContract({
    ...closedLeaderParameters,
    query: {
      enabled: onAnvil && round.data !== undefined && round.data > 0n,
    },
  });

  const farm0 = useListedFarm(0, strategyCount.data, onAnvil);
  const farm1 = useListedFarm(1, strategyCount.data, onAnvil);
  const farm2 = useListedFarm(2, strategyCount.data, onAnvil);
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

  const approve = useAnvilAction({
    abi: driverTokenAbi,
    account: address,
    address: anvilContracts.driverToken,
    args: [anvilContracts.driverVote, lockAmount] as const,
    describeError,
    describeReceiptError,
    functionName: "approve",
    scope: identity,
  });
  const lock = useAnvilAction({
    abi: driverVoteAbi,
    account: address,
    address: anvilContracts.driverVote,
    args: [lockAmount] as const,
    describeError,
    describeReceiptError,
    functionName: "lock",
    scope: identity,
  });
  const unlock = useAnvilAction({
    abi: driverVoteAbi,
    account: address,
    address: anvilContracts.driverVote,
    args: [unlockAmount] as const,
    describeError,
    describeReceiptError,
    functionName: "unlock",
    scope: identity,
  });
  const vote = useAnvilAction({
    abi: driverVoteAbi,
    account: address,
    address: anvilContracts.driverVote,
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
    onAnvil &&
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
  } else if (!onAnvil) {
    status = "Switch to Anvil to lock and vote.";
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

  if (connection.isConnected && !onAnvil) {
    return (
      <section className={sectionClass()}>
        <h2 className={headingClass()}>Lock and vote</h2>
        <p>Switch to Anvil to lock and vote.</p>
      </section>
    );
  }

  return (
    <section className={sectionClass()}>
      <h2 className={headingClass()}>Lock and vote</h2>
      {accountReady ? (
        <p className="tabular-nums">Locked: {formatDvr(locked.data ?? 0n)} DVR</p>
      ) : null}
      {round.data !== undefined ? (
        <p className="tabular-nums">Open round: {round.data.toString()}</p>
      ) : null}
      {farmsReady ? (
        <p>
          Open round leader:{" "}
          {openChoice === undefined
            ? "No votes yet."
            : (labels.get(openChoice) ?? openChoice)}
        </p>
      ) : null}
      {farmsReady && round.data !== undefined && round.data > 0n ? (
        <p>
          Round {closedRound.toString()} choice:{" "}
          {closedChoice === undefined
            ? "No votes."
            : (labels.get(closedChoice) ?? closedChoice)}
        </p>
      ) : null}
      {currentVote !== undefined ? (
        <p>Your vote: {labels.get(currentVote) ?? currentVote}</p>
      ) : null}
      {listed.map((farm) =>
        farm.farm === undefined || farm.tally.data === undefined ? null : (
          <label key={farm.farm} className="flex items-center gap-2">
            <input
              type="radio"
              name="farm"
              checked={selected === farm.farm}
              onChange={() => {
                setSelected(farm.farm);
              }}
            />
            <span className="tabular-nums">
              {labels.get(farm.farm) ?? farm.farm}: {formatDvr(farm.tally.data)} DVR
            </span>
          </label>
        ),
      )}
      <label className="flex flex-col gap-1">
        Lock amount
        <input
          className={inputClass()}
          inputMode="decimal"
          value={lockText}
          onChange={(event) => {
            setLockText(event.target.value);
          }}
        />
      </label>
      <label className="flex flex-col gap-1">
        Unlock amount
        <input
          className={inputClass()}
          inputMode="decimal"
          value={unlockText}
          onChange={(event) => {
            setUnlockText(event.target.value);
          }}
        />
      </label>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className={actionButtonClass()}
          disabled={!canLock}
          onClick={() => {
            void onLock();
          }}
        >
          Lock DVR
        </button>
        <button
          type="button"
          className={actionButtonClass()}
          disabled={!canUnlock}
          onClick={() => {
            void onUnlock();
          }}
        >
          Unlock DVR
        </button>
        <button
          type="button"
          className={actionButtonClass()}
          disabled={!canVote}
          onClick={() => {
            void onVote();
          }}
        >
          Vote
        </button>
      </div>
      {status ? <p>{status}</p> : null}
      {lockReason && !busy ? <p>{lockReason}</p> : null}
      {unlockReason && !busy ? <p>{unlockReason}</p> : null}
      {voteReason && !busy ? <p>{voteReason}</p> : null}
      {unlockCountdown ? <p className="tabular-nums">{unlockCountdown}</p> : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
    </section>
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
