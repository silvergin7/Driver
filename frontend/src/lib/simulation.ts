import simulationFile from "../content/simulation.json";
import { formatDvr } from "./format-dvr";
import { formatUsdc } from "./format-usdc";

export const swapChoices = [
  { id: "25", usdc: "25000000", label: "25 mUSDC" },
  { id: "50", usdc: "50000000", label: "50 mUSDC" },
  { id: "100", usdc: "100000000", label: "100 mUSDC" },
] as const;

export const lockChoices = [
  { id: "half", label: "Half" },
  { id: "all", label: "All" },
] as const;

export const voteChoices = [
  { id: "highway", label: "Highway" },
  { id: "autobahn", label: "Autobahn" },
  { id: "drift", label: "Drift" },
] as const;

export type SwapChoice = (typeof swapChoices)[number]["id"];
export type LockChoice = (typeof lockChoices)[number]["id"];
export type VoteChoice = (typeof voteChoices)[number]["id"];

export type SimulationStep = {
  id: string;
  walletDvr: string;
  walletUsdc: string;
  lockedDvr: string;
  poolDvr: string;
  poolUsdc: string;
  taxFund1: string;
  taxFund2: string;
  taxFund3: string;
  fund1Value: string;
  fund2Value: string;
  fund1Pending: string;
  fund2Pending: string;
  fund1BoughtBack: string;
  fund2BoughtBack: string;
  fund1BuybackSpent: string;
  fund1DvrBurned: string;
  fund2BuybackSpent: string;
  fund2DvrBurned: string;
  totalSupply: string;
  rebalanceAmount: string;
};

export type SimulationRun = {
  swapUsdc: string;
  lock: LockChoice;
  vote: VoteChoice;
  steps: SimulationStep[];
};

type SimulationFile = {
  startTimestamp: string;
  epochSeconds: string;
  runs: SimulationRun[];
};

export const simulation = simulationFile as SimulationFile;

export const stepCopy = [
  {
    id: "start",
    title: "A fresh deployment",
    text: "Nobody has claimed, traded, or voted yet. The pool still prices DVR at its starting rate, and both funds hold the money they were given.",
  },
  {
    id: "claim",
    title: "Claim the faucets",
    text: "The faucets pay 10 DVR and 100 mUSDC from tokens that already exist. They do not mint new DVR.",
  },
  {
    id: "swap",
    title: "Buy DVR",
    text: "You spend mUSDC in the official pool. One percent of it is tax for the funds, and that tax never enters the pool.",
  },
  {
    id: "lock",
    title: "Lock DVR",
    text: "Locked DVR is your vote. One locked DVR is one vote, so the same coins cannot be used twice.",
  },
  {
    id: "vote",
    title: "Choose a speed",
    text: "This vote tells Degen Driver which farm to use. Cruise Control stays at 5% either way.",
  },
  {
    id: "skip",
    title: "Skip 30 days",
    text: "The demo clock jumps one round, so the farms can earn and the vote can close. Faucet waits still use real time.",
  },
  {
    id: "harvest-fund-1",
    title: "Harvest Cruise Control",
    text: "Its tax comes in. Half of what the farm earned goes back in, and the other half buys DVR and burns it.",
  },
  {
    id: "harvest-fund-2",
    title: "Harvest Degen Driver",
    text: "The vote is applied and the fund's money goes into the chosen farm. Nothing moves to Cruise Control yet, because Degen Driver was parked and earned nothing.",
  },
  {
    id: "skip-again",
    title: "Skip another 30 days",
    text: "The chosen farm is holding the money now, so this month it earns.",
  },
  {
    id: "harvest-fund-1-again",
    title: "Harvest Cruise Control again",
    text: "The careful fund earns another month at 5%. Half of that buys DVR and burns it.",
  },
  {
    id: "harvest-fund-2-again",
    title: "Harvest Degen Driver again",
    text: "Half of what the chosen farm earned buys and burns DVR. If Cruise Control is below three quarters of the two funds, Degen Driver tops it up.",
  },
] as const;

export function findRun(
  swap: SwapChoice,
  lock: LockChoice,
  vote: VoteChoice,
): SimulationRun {
  const usdc = swapChoices.find((choice) => choice.id === swap)?.usdc;
  const run = simulation.runs.find(
    (item) =>
      item.swapUsdc === usdc && item.lock === lock && item.vote === vote,
  );
  if (run === undefined) {
    throw new Error(`No simulation run for ${swap}, ${lock}, ${vote}.`);
  }
  return run;
}

export function stepIndexAfter(
  current: number,
  count: number,
  action: "back" | "next" | "start",
): number {
  if (action === "start" || count === 0) {
    return 0;
  }
  if (action === "back") {
    return current <= 0 ? 0 : current - 1;
  }
  return current + 1 >= count ? current : current + 1;
}

export function priceUsdcPerDvr(poolDvr: bigint, poolUsdc: bigint): string {
  if (poolDvr === 0n) {
    return "Unavailable.";
  }
  return formatUsdc((poolUsdc * 10n ** 18n) / poolDvr);
}

export function stepRows(
  steps: readonly SimulationStep[],
  index: number,
): { label: string; value: string }[] {
  const step = steps[index];
  const previous = index > 0 ? steps[index - 1] : undefined;
  if (step === undefined) {
    return [];
  }
  const supply = BigInt(steps[0]?.totalSupply ?? step.totalSupply);
  const price = (poolDvr: string, poolUsdc: string) =>
    `${priceUsdcPerDvr(BigInt(poolDvr), BigInt(poolUsdc))} mUSDC`;
  return [
    amountRow("Your DVR", previous?.walletDvr, step.walletDvr, formatDvr, " DVR"),
    amountRow("Your mUSDC", previous?.walletUsdc, step.walletUsdc, formatUsdc, " mUSDC"),
    amountRow("Locked DVR", previous?.lockedDvr, step.lockedDvr, formatDvr, " DVR"),
    amountRow("Pool DVR", previous?.poolDvr, step.poolDvr, formatDvr, " DVR"),
    amountRow("Pool mUSDC", previous?.poolUsdc, step.poolUsdc, formatUsdc, " mUSDC"),
    {
      label: "Price",
      value: changed(
        previous === undefined ? undefined : price(previous.poolDvr, previous.poolUsdc),
        price(step.poolDvr, step.poolUsdc),
      ),
    },
    amountRow("Cruise Control tax", previous?.taxFund1, step.taxFund1, formatUsdc, " mUSDC"),
    amountRow("Degen Driver tax", previous?.taxFund2, step.taxFund2, formatUsdc, " mUSDC"),
    amountRow("Unassigned tax", previous?.taxFund3, step.taxFund3, formatUsdc, " mUSDC"),
    amountRow("Cruise Control", previous?.fund1Value, step.fund1Value, formatUsdc, " mUSDC"),
    amountRow("Degen Driver", previous?.fund2Value, step.fund2Value, formatUsdc, " mUSDC"),
    amountRow(
      "Cruise Control rewards",
      previous?.fund1Pending,
      step.fund1Pending,
      formatUsdc,
      " mUSDC",
    ),
    amountRow(
      "Degen Driver rewards",
      previous?.fund2Pending,
      step.fund2Pending,
      formatUsdc,
      " mUSDC",
    ),
    amountRow(
      "DVR burned",
      previous === undefined ? undefined : burned(supply, previous.totalSupply),
      burned(supply, step.totalSupply),
      formatDvr,
      " DVR",
    ),
    {
      label: "Total supply",
      value: changed(
        previous === undefined
          ? undefined
          : `${formatDvr(BigInt(previous.totalSupply))} DVR`,
        `${formatDvr(BigInt(step.totalSupply))} DVR`,
      ),
    },
    amountRow(
      "Moved to Cruise Control",
      previous?.rebalanceAmount,
      step.rebalanceAmount,
      formatUsdc,
      " mUSDC",
    ),
  ];
}

function burned(supply: bigint, current: string): string {
  return (supply - BigInt(current)).toString();
}

function amountRow(
  label: string,
  before: string | undefined,
  after: string,
  format: (value: bigint) => string,
  suffix: string,
): { label: string; value: string } {
  return {
    label,
    value: changed(
      before === undefined ? undefined : `${format(BigInt(before))}${suffix}`,
      `${format(BigInt(after))}${suffix}`,
    ),
  };
}

function changed(before: string | undefined, after: string): string {
  if (before === undefined || before === after) {
    return after;
  }
  return `${before} → ${after}`;
}
