"use client";

import { useState } from "react";
import type { Abi } from "viem";
import { useConfig, useConnection, useReadContract } from "wagmi";
import { getBlock, readContract } from "wagmi/actions";
import { anvil, contracts } from "@/config/contracts";
import {
  driverTokenAbi,
  mockUsdcAbi,
  officialPoolAbi,
  taxSplitterAbi,
} from "@/generated/contracts";
import { useAnvilAction } from "@/hooks/use-anvil-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import {
  choiceButtonClass,
  fitActionButtonClass,
  inputClass,
} from "@/lib/control-class";
import { Card } from "@/components/ui/card";
import { StatList } from "@/components/ui/stat-list";
import { formatDvr } from "@/lib/format-dvr";
import { formatUsdc } from "@/lib/format-usdc";
import { parseTokenAmount, type ParsedAmount } from "@/lib/parse-amount";
import { minAmountAfterSlippage, slippageBps } from "@/lib/slippage";

const anvilContracts = contracts[anvil.id];
const deadlineBuffer = 1_200n;
const failed = "The transaction failed.";
const reverted = "The transaction reverted.";
const poolAbi = officialPoolAbi as Abi;
const tokenAbi = driverTokenAbi as Abi;
const usdcAbi = mockUsdcAbi as Abi;

function describeError(error: unknown): string {
  return actionErrorMessage(error, [poolAbi, tokenAbi, usdcAbi], failed);
}

function describeReceiptError(error: unknown): string {
  return actionReceiptErrorMessage(error, [poolAbi, tokenAbi, usdcAbi], reverted);
}

export function PoolSwap() {
  const connection = useConnection();
  const config = useConfig();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const address = onAnvil ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const [direction, setDirection] = useState<"buy" | "sell">("buy");
  const [text, setText] = useState("");
  const [notice, setNotice] = useState<string>();
  const [actionError, setActionError] = useState<string>();
  const [noticeScope, setNoticeScope] = useState(identity);
  if (noticeScope !== identity) {
    setNoticeScope(identity);
    setNotice(undefined);
    setActionError(undefined);
  }

  const buying = direction === "buy";
  const parsed = parseTokenAmount(text, buying ? 6 : 18);
  const amount = parsed.status === "amount" ? parsed.amount : 0n;
  const spentAbi = buying ? mockUsdcAbi : driverTokenAbi;
  const spentAddress = buying
    ? anvilContracts.mockUsdc
    : anvilContracts.driverToken;
  const accountArgs = address === undefined ? undefined : ([address] as const);
  const balance = useReadContract({
    abi: spentAbi,
    address: spentAddress,
    args: accountArgs,
    chainId: anvil.id,
    functionName: "balanceOf",
    query: { enabled: address !== undefined },
  });
  const allowance = useReadContract({
    abi: spentAbi,
    address: spentAddress,
    args:
      address === undefined
        ? undefined
        : ([address, anvilContracts.officialPool] as const),
    chainId: anvil.id,
    functionName: "allowance",
    query: { enabled: address !== undefined },
  });
  const quote = useReadContract({
    abi: officialPoolAbi,
    address: anvilContracts.officialPool,
    args: [buying ? 0 : 1, amount] as const,
    chainId: anvil.id,
    functionName: "quoteExactInput",
    query: { enabled: onAnvil && parsed.status === "amount" },
  });
  const taxParameters = {
    abi: officialPoolAbi,
    address: anvilContracts.officialPool,
    chainId: anvil.id,
    functionName: "taxBps",
    query: { enabled: onAnvil },
  } as const;
  const taxBps = useReadContract({
    ...taxParameters,
    query: { enabled: onAnvil },
  });
  const fund1Tax = useAccrued(0, onAnvil);
  const fund2Tax = useAccrued(1, onAnvil);
  const unassignedTax = useAccrued(2, onAnvil);

  const approve = useAnvilAction({
    abi: spentAbi,
    account: address,
    address: spentAddress,
    args: [anvilContracts.officialPool, amount] as const,
    describeError,
    describeReceiptError,
    functionName: "approve",
    scope: `${identity}:${direction}`,
  });
  const swap = useAnvilAction({
    abi: officialPoolAbi,
    account: address,
    address: anvilContracts.officialPool,
    args: [buying ? 0 : 1, amount, 0n, 0n] as const,
    describeError,
    describeReceiptError,
    functionName: "swapExactInput",
    scope: identity,
  });

  const busy = approve.busy || swap.busy;
  const ready =
    address !== undefined &&
    balance.data !== undefined &&
    allowance.data !== undefined &&
    fund1Tax.data !== undefined &&
    fund2Tax.data !== undefined &&
    unassignedTax.data !== undefined;
  const readsFailed =
    onAnvil &&
    (unread(balance) ||
      unread(allowance) ||
      unread(taxBps) ||
      unread(fund1Tax) ||
      unread(fund2Tax) ||
      unread(unassignedTax));
  const amountReason = swapAmountReason(parsed, balance.data);
  const quotedOut = quote.data?.[0];
  const quotedTax = quote.data?.[1];
  const canSwap =
    ready &&
    parsed.status === "amount" &&
    amountReason === undefined &&
    quotedOut !== undefined &&
    quotedOut > 0n &&
    !quote.isError &&
    !busy;

  async function onSwap(): Promise<void> {
    if (
      parsed.status !== "amount" ||
      allowance.data === undefined ||
      address === undefined
    ) {
      return;
    }
    setNotice(undefined);
    setActionError(undefined);
    const latest = await getBlock(config, { chainId: anvil.id });
    let minOut: bigint;
    try {
      const fresh = await readContract(config, {
        abi: officialPoolAbi,
        address: anvilContracts.officialPool,
        args: [buying ? 0 : 1, parsed.amount],
        chainId: anvil.id,
        functionName: "quoteExactInput",
      });
      if (fresh[0] === 0n) {
        setActionError("The swap would return no tokens.");
        return;
      }
      minOut = minAmountAfterSlippage(fresh[0]);
    } catch (error) {
      setActionError(describeError(error));
      return;
    }
    if (allowance.data < parsed.amount) {
      const approved = await approve.send([
        anvilContracts.officialPool,
        parsed.amount,
      ]);
      if (!approved) {
        return;
      }
    }
    const swapped = await swap.send([
      buying ? 0 : 1,
      parsed.amount,
      minOut,
      latest.timestamp + deadlineBuffer,
    ]);
    if (swapped) {
      setNotice(buying ? "Bought DVR." : "Sold DVR.");
    }
  }

  let status: string | undefined;
  if (!connection.isConnected) {
    status = "Connect a wallet to swap.";
  } else if (!onAnvil) {
    status = "Switch to Anvil to swap.";
  } else if (readsFailed) {
    status = "Swap status unavailable.";
  } else if (!ready) {
    status = "Loading the pool…";
  } else if (approve.simulating) {
    status = "Checking the approval.";
  } else if (approve.writePending || swap.writePending) {
    status = "Waiting for the wallet.";
  } else if (approve.confirming) {
    status = "Confirming the approval.";
  } else if (swap.simulating) {
    status = "Checking the swap.";
  } else if (swap.confirming) {
    status = "Confirming the swap.";
  } else if (notice) {
    status = notice;
  }

  if (connection.isConnected && !onAnvil) {
    return (
      <Card title="Official pool">
        <p className="text-sm text-ink-muted">Switch to Anvil to swap.</p>
      </Card>
    );
  }

  const poolStats = [
    taxBps.data !== undefined
      ? { label: "Tax", value: `${taxBps.data / 100n}%` }
      : undefined,
    { label: "Slippage", value: `${slippageBps / 100n}%` },
  ].filter((row): row is { label: string; value: string } => row !== undefined);

  return (
    <Card title="Official pool">
      <StatList rows={poolStats} />
      <div className="flex gap-2">
        <button
          type="button"
          aria-pressed={buying}
          className={directionClass(buying)}
          disabled={busy}
          onClick={() => {
            if (buying) {
              return;
            }
            setDirection("buy");
            setText("");
            setNotice(undefined);
          }}
        >
          Buy
        </button>
        <button
          type="button"
          aria-pressed={!buying}
          className={directionClass(!buying)}
          disabled={busy}
          onClick={() => {
            if (!buying) {
              return;
            }
            setDirection("sell");
            setText("");
            setNotice(undefined);
          }}
        >
          Sell
        </button>
      </div>
      <div className="flex items-end gap-2">
        <label className="flex min-w-0 flex-1 flex-col gap-1 text-sm text-ink-muted">
          {buying ? "mUSDC to spend" : "DVR to spend"}
          <input
            className={`${inputClass()} w-full`}
            inputMode="decimal"
            value={text}
            onChange={(event) => {
              setText(event.target.value);
            }}
          />
        </label>
        <button
          type="button"
          className={`${fitActionButtonClass()} shrink-0 whitespace-nowrap`}
          disabled={!canSwap}
          onClick={() => {
            void onSwap();
          }}
        >
          {buying ? "Buy DVR" : "Sell DVR"}
        </button>
      </div>
      {quotedOut !== undefined && quotedTax !== undefined && parsed.status === "amount" ? (
        <p className="text-sm text-ink tabular-nums">
          Quote: {buying ? formatDvr(quotedOut) : formatUsdc(quotedOut)}{" "}
          {buying ? "DVR" : "mUSDC"}, tax {formatUsdc(quotedTax)} mUSDC
        </p>
      ) : null}
      {fund1Tax.data !== undefined &&
      fund2Tax.data !== undefined &&
      unassignedTax.data !== undefined ? (
        <StatList
          title="Tax collected"
          rows={[
            { label: "Fund 1", value: `${formatUsdc(fund1Tax.data)} mUSDC` },
            { label: "Fund 2", value: `${formatUsdc(fund2Tax.data)} mUSDC` },
            { label: "Unassigned", value: `${formatUsdc(unassignedTax.data)} mUSDC` },
          ]}
        />
      ) : null}
      {status ? <p className="text-sm text-ink-muted">{status}</p> : null}
      {amountReason && !busy ? <p className="text-sm text-ink-muted">{amountReason}</p> : null}
      {parsed.status === "amount" && quotedOut === 0n ? (
        <p className="text-sm text-ink-muted">The swap would return no tokens.</p>
      ) : null}
      {actionError ?? approve.errorMessage ?? swap.errorMessage ? (
        <p role="alert">
          {actionError ?? approve.errorMessage ?? swap.errorMessage}
        </p>
      ) : null}
      {quote.isError ? <p role="alert">{describeError(quote.error)}</p> : null}
    </Card>
  );
}

function useAccrued(fundId: 0 | 1 | 2, enabled: boolean) {
  return useReadContract({
    abi: taxSplitterAbi,
    address: anvilContracts.taxSplitter,
    args: [fundId] as const,
    chainId: anvil.id,
    functionName: "accrued",
    query: { enabled },
  });
}

function directionClass(pressed: boolean): string {
  return choiceButtonClass(pressed);
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}

function swapAmountReason(
  parsed: ParsedAmount,
  balance: bigint | undefined,
): string | undefined {
  if (parsed.status === "empty") {
    return undefined;
  }
  if (parsed.status === "invalid") {
    return "Enter an amount.";
  }
  if (parsed.status === "zero") {
    return "Enter an amount above zero.";
  }
  if (balance !== undefined && parsed.amount > balance) {
    return "That is more than the wallet holds.";
  }
  return undefined;
}
