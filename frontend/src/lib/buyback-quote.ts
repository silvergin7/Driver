import { minAmountAfterSlippage } from "./slippage";

export type BuybackQuote =
  | { status: "waiting" }
  | { status: "defer" }
  | { status: "block" }
  | { status: "quoted"; amountOut: bigint; usdcTax: bigint };

export type BuybackPlan =
  | { status: "skip"; spend: 0n; minDvrOut: 0n }
  | { status: "ready"; spend: bigint; minDvrOut: bigint }
  | { status: "blocked" }
  | { status: "waiting" };

export function buybackSpend(input: {
  heldRewards: bigint;
  pendingRewards: bigint;
  rewardReserve: bigint;
  hasActiveFarm: boolean;
  pendingBuyback: bigint;
}): { half: bigint; spend: bigint } {
  const pending = input.hasActiveFarm
    ? min(input.pendingRewards, input.rewardReserve)
    : 0n;
  const half = (input.heldRewards + pending) / 2n;
  if (half === 0n) {
    return { half, spend: 0n };
  }
  return { half, spend: half + input.pendingBuyback };
}

export function planBuyback(input: {
  heldRewards: bigint;
  pendingRewards: bigint;
  rewardReserve: bigint;
  hasActiveFarm: boolean;
  pendingBuyback: bigint;
  quote: BuybackQuote;
}): BuybackPlan {
  const { half, spend } = buybackSpend(input);
  if (half === 0n) {
    return { status: "skip", spend: 0n, minDvrOut: 0n };
  }
  if (input.quote.status === "waiting") {
    return { status: "waiting" };
  }
  if (input.quote.status === "block") {
    return { status: "blocked" };
  }
  if (
    input.quote.status === "defer" ||
    (input.quote.status === "quoted" &&
      (input.quote.amountOut === 0n || input.quote.usdcTax > spend))
  ) {
    return { status: "skip", spend: 0n, minDvrOut: 0n };
  }
  if (input.quote.status !== "quoted") {
    return { status: "blocked" };
  }
  return {
    status: "ready",
    spend,
    minDvrOut: minAmountAfterSlippage(input.quote.amountOut),
  };
}

export function deferredQuoteError(errorName: string | undefined): boolean {
  return (
    errorName === "OfficialPool__ZeroAmount" ||
    errorName === "OfficialPool__ZeroOutput"
  );
}

function min(left: bigint, right: bigint): bigint {
  return left < right ? left : right;
}
