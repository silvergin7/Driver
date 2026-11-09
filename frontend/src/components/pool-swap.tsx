"use client";

import { useRef, useState } from "react";
import type { Abi } from "viem";
import { useConfig, useConnection, useReadContract } from "wagmi";
import { getBlock, readContract } from "wagmi/actions";
import { chain, chainLabel, contracts } from "@/config/contracts";
import { switchPrompt } from "@/lib/switch-prompt";
import {
  driverTokenAbi,
  mockUsdcAbi,
  officialPoolAbi,
  taxSplitterAbi,
} from "@/generated/contracts";
import { useChainAction } from "@/hooks/use-chain-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import { Pump, readoutClass } from "@/components/pump-frame";
import { TokenIcon } from "@/components/token-icon";
import { publishConfirmed, useFailureToast } from "@/components/toaster";
import { TransactionLink } from "@/components/transaction-link";
import { formatDisplayAmount } from "@/lib/format-display";
import { formatUsdc } from "@/lib/format-usdc";
import { maxAmountText } from "@/lib/max-amount";
import { motionAllowed } from "@/lib/motion";
import { parseTokenAmount, type ParsedAmount } from "@/lib/parse-amount";
import { minAmountAfterSlippage, slippageBps } from "@/lib/slippage";

const chainContracts = contracts[chain.id];
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
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const address = onChain ? connection.address : undefined;
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
    ? chainContracts.mockUsdc
    : chainContracts.driverToken;
  const accountArgs = address === undefined ? undefined : ([address] as const);
  const balance = useReadContract({
    abi: spentAbi,
    address: spentAddress,
    args: accountArgs,
    chainId: chain.id,
    functionName: "balanceOf",
    query: { enabled: address !== undefined },
  });
  const allowance = useReadContract({
    abi: spentAbi,
    address: spentAddress,
    args:
      address === undefined
        ? undefined
        : ([address, chainContracts.officialPool] as const),
    chainId: chain.id,
    functionName: "allowance",
    query: { enabled: address !== undefined },
  });
  const quote = useReadContract({
    abi: officialPoolAbi,
    address: chainContracts.officialPool,
    args: [buying ? 0 : 1, amount] as const,
    chainId: chain.id,
    functionName: "quoteExactInput",
    query: { enabled: onChain && parsed.status === "amount" },
  });
  const taxParameters = {
    abi: officialPoolAbi,
    address: chainContracts.officialPool,
    chainId: chain.id,
    functionName: "taxBps",
    query: { enabled: onChain },
  } as const;
  const taxBps = useReadContract({
    ...taxParameters,
    query: { enabled: onChain },
  });
  const fund1Tax = useAccrued(0, onChain);
  const fund2Tax = useAccrued(1, onChain);
  const unassignedTax = useAccrued(2, onChain);

  const approve = useChainAction({
    abi: spentAbi,
    account: address,
    address: spentAddress,
    args: [chainContracts.officialPool, amount] as const,
    describeError,
    describeReceiptError,
    functionName: "approve",
    scope: `${identity}:${direction}`,
  });
  const swap = useChainAction({
    abi: officialPoolAbi,
    account: address,
    address: chainContracts.officialPool,
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
    onChain &&
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
  const flipRef = useRef<HTMLButtonElement>(null);
  const spin = useRef<Animation | null>(null);
  const turn = useRef(0);

  function fillMax(): void {
    if (balance.data === undefined) {
      return;
    }
    setText(maxAmountText(balance.data, buying ? 6 : 18));
    setNotice(undefined);
  }

  function flip(): void {
    setDirection(buying ? "sell" : "buy");
    setText("");
    setNotice(undefined);
    const button = flipRef.current;
    if (button === null) {
      return;
    }
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!motionAllowed(reduced)) {
      return;
    }
    spin.current?.cancel();
    const from = turn.current;
    turn.current += 180;
    spin.current = button.animate(
      [
        { transform: `rotate(${from}deg)` },
        { transform: `rotate(${turn.current}deg)` },
      ],
      { duration: 300, easing: "ease-out", fill: "forwards" },
    );
  }

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
    const latest = await getBlock(config, { chainId: chain.id });
    let minOut: bigint;
    try {
      const fresh = await readContract(config, {
        abi: officialPoolAbi,
        address: chainContracts.officialPool,
        args: [buying ? 0 : 1, parsed.amount],
        chainId: chain.id,
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
        chainContracts.officialPool,
        parsed.amount,
      ]);
      if (!approved) {
        return;
      }
      publishConfirmed("Approved.");
    }
    const swapped = await swap.send([
      buying ? 0 : 1,
      parsed.amount,
      minOut,
      latest.timestamp + deadlineBuffer,
    ]);
    if (swapped) {
      const sentence = buying ? "Bought DVR." : "Sold DVR.";
      setNotice(sentence);
      publishConfirmed(sentence);
    }
  }

  let status: string | undefined;
  if (!connection.isConnected) {
    status = "Connect a wallet to swap.";
  } else if (!onChain) {
    status = switchPrompt(chainLabel, "to swap.");
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

  const getText =
    quotedOut !== undefined && parsed.status === "amount"
      ? formatDisplayAmount(quotedOut, buying ? 18 : 6)
      : "0";
  const minimum =
    quotedOut !== undefined && parsed.status === "amount"
      ? buying
        ? `${formatDisplayAmount(minAmountAfterSlippage(quotedOut), 18)} DVR`
        : `${formatDisplayAmount(minAmountAfterSlippage(quotedOut), 6)} mUSDC`
      : undefined;

  const shownError =
    actionError ??
    approve.errorMessage ??
    swap.errorMessage ??
    (quote.isError ? describeError(quote.error) : undefined);
  useFailureToast(shownError);

  if (connection.isConnected && !onChain) {
    return (
      <Pump title="Official pool" bandClass="bg-brand">
        <p className="text-sm text-ink-muted">{switchPrompt(chainLabel, "to swap.")}</p>
      </Pump>
    );
  }

  return (
    <Pump title="Official pool" bandClass="bg-brand">
      <div className={`${readoutClass} overflow-hidden`}>
        <p className="text-sm text-slate-300">You pay</p>
        <div className="mt-2 flex min-w-0 items-center gap-2">
          <TokenChip token={buying ? "musdc" : "dvr"} />
          <input
            className="min-w-0 flex-1 overflow-x-auto bg-transparent font-mono text-2xl text-slate-50 outline-none sm:text-3xl"
            inputMode="decimal"
            aria-label={buying ? "mUSDC to spend" : "DVR to spend"}
            value={text}
            onChange={(event) => {
              setText(event.target.value);
            }}
          />
        </div>
        <div className="my-3 flex items-center justify-center gap-2">
          <button
            ref={flipRef}
            type="button"
            aria-label="Flip direction"
            className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full border-2 border-sign text-slate-50 disabled:opacity-40"
            disabled={busy}
            onClick={flip}
          >
            <FlipIcon />
          </button>
          <button
            type="button"
            className="h-11 shrink-0 rounded-full border border-slate-500 px-3 text-sm text-slate-50 disabled:opacity-40"
            disabled={balance.data === undefined || busy}
            onClick={fillMax}
          >
            Max
          </button>
        </div>
        <p className="text-sm text-slate-300">You get</p>
        <div className="mt-2 flex min-w-0 items-center gap-2">
          <TokenChip token={buying ? "dvr" : "musdc"} />
          <p className="min-w-0 flex-1 overflow-hidden font-mono text-2xl whitespace-nowrap text-ellipsis tabular-nums sm:text-3xl">
            {getText}
          </p>
        </div>
      </div>
      <dl className="grid gap-2 border-t border-line pt-3 text-sm sm:grid-cols-2">
        {taxBps.data !== undefined ? (
          <div>
            <dt className="text-ink-muted">Tax</dt>
            <dd className="text-ink">
              {`${taxBps.data / 100n}% tax`}
              {quotedTax !== undefined && parsed.status === "amount"
                ? ` · ${formatUsdc(quotedTax)} mUSDC`
                : ""}
            </dd>
          </div>
        ) : null}
        <div>
          <dt className="text-ink-muted">Slippage</dt>
          <dd className="text-ink">{`${slippageBps / 100n}%`}</dd>
        </div>
        {minimum !== undefined ? (
          <div>
            <dt className="text-ink-muted">{"Minimum you'll get"}</dt>
            <dd className="text-ink">{minimum}</dd>
          </div>
        ) : null}
        {fund1Tax.data !== undefined &&
        fund2Tax.data !== undefined &&
        unassignedTax.data !== undefined ? (
          <>
            <div>
              <dt className="text-ink-muted">Fund 1</dt>
              <dd className="text-ink">{`${formatUsdc(fund1Tax.data)} mUSDC`}</dd>
            </div>
            <div>
              <dt className="text-ink-muted">Fund 2</dt>
              <dd className="text-ink">{`${formatUsdc(fund2Tax.data)} mUSDC`}</dd>
            </div>
            <div>
              <dt className="text-ink-muted">Unassigned</dt>
              <dd className="text-ink">{`${formatUsdc(unassignedTax.data)} mUSDC`}</dd>
            </div>
          </>
        ) : null}
      </dl>
      <button
        type="button"
        className="min-h-12 w-full rounded-md bg-brand px-3 py-2 text-lg text-on-brand disabled:border disabled:border-line disabled:bg-disabled-bg disabled:text-ink-muted"
        disabled={!canSwap}
        onClick={() => {
          void onSwap();
        }}
      >
        Swap
      </button>
      {status ? <p className="text-sm text-ink-muted">{status}</p> : null}
      <TransactionLink hash={swap.isSuccess ? swap.hash : undefined} />
      {amountReason && !busy ? <p className="text-sm text-ink-muted">{amountReason}</p> : null}
      {parsed.status === "amount" && quotedOut === 0n ? (
        <p className="text-sm text-ink-muted">The swap would return no tokens.</p>
      ) : null}
      {actionError ?? approve.errorMessage ?? swap.errorMessage ? (
        <p role="alert">{actionError ?? approve.errorMessage ?? swap.errorMessage}</p>
      ) : null}
      {quote.isError ? <p role="alert">{describeError(quote.error)}</p> : null}
    </Pump>
  );
}

function useAccrued(fundId: 0 | 1 | 2, enabled: boolean) {
  return useReadContract({
    abi: taxSplitterAbi,
    address: chainContracts.taxSplitter,
    args: [fundId] as const,
    chainId: chain.id,
    functionName: "accrued",
    query: { enabled },
  });
}

function TokenChip({ token }: { token: "dvr" | "musdc" }) {
  return (
    <span className="inline-flex h-11 shrink-0 items-center gap-1 rounded-full border border-slate-500 px-2 text-sm font-semibold text-slate-50">
      <TokenIcon token={token} className={token === "dvr" ? "h-5 w-7" : "h-5 w-5"} />
      {token === "dvr" ? "DVR" : "mUSDC"}
    </span>
  );
}

function FlipIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-5 w-5">
      <path
        d="M7 7h10l-3-3M17 17H7l3 3"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
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
