"use client";

import { useState } from "react";
import {
  BaseError,
  ContractFunctionRevertedError,
  getAddress,
  zeroAddress,
  type Abi,
  type Address,
} from "viem";
import { sepolia } from "viem/chains";
import { useConfig, useConnection, useReadContract } from "wagmi";
import { readContract } from "wagmi/actions";
import { chain, chainLabel, contracts } from "@/config/contracts";
import { switchPrompt } from "@/lib/switch-prompt";
import {
  cruiseControlAbi,
  degenDriverAbi,
  demoDriverClockAbi,
  mockFarmAbi,
  officialPoolAbi,
  roundScheduleAbi,
} from "@/generated/contracts";
import { useChainAction } from "@/hooks/use-chain-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import { actionButtonClass } from "@/lib/control-class";
import { Card } from "@/components/ui/card";
import { StatList } from "@/components/ui/stat-list";
import {
  buybackSpend,
  deferredQuoteError,
  planBuyback,
  type BuybackPlan,
  type BuybackQuote,
} from "@/lib/buyback-quote";
import { ownerCardView } from "@/lib/owner-card";
import { slippageBps } from "@/lib/slippage";

const chainContracts = contracts[chain.id];
const failed = "The transaction failed.";
const reverted = "The transaction reverted.";
const day = 86_400n;

const harvestAbis = [
  cruiseControlAbi,
  degenDriverAbi,
  officialPoolAbi,
  mockFarmAbi,
] as Abi[];

function describeError(error: unknown): string {
  return actionErrorMessage(error, harvestAbis, failed);
}

function describeReceiptError(error: unknown): string {
  return actionReceiptErrorMessage(error, harvestAbis, reverted);
}

function revertName(error: unknown): string | undefined {
  if (!(error instanceof BaseError)) {
    return undefined;
  }
  const reverted = error.walk(
    (cause) => cause instanceof ContractFunctionRevertedError,
  );
  if (!(reverted instanceof ContractFunctionRevertedError)) {
    return undefined;
  }
  return reverted.data?.errorName;
}

export function OwnerControls() {
  const connection = useConnection();
  const config = useConfig();
  const connected = connection.isConnected;
  const onChain = connected && connection.chainId === chain.id;
  const readAddress = connected ? connection.address : undefined;
  const actionAddress = onChain ? connection.address : undefined;
  const identity = `${readAddress ?? "disconnected"}:${connection.chainId ?? "none"}`;
  const [notice, setNotice] = useState<string>();
  const [quoteError, setQuoteError] = useState<string>();
  const [noticeScope, setNoticeScope] = useState(identity);
  if (noticeScope !== identity) {
    setNoticeScope(identity);
    setNotice(undefined);
    setQuoteError(undefined);
  }

  const cruiseOwner = useReadContract({
    abi: cruiseControlAbi,
    address: chainContracts.cruiseControl,
    chainId: chain.id,
    functionName: "owner",
    query: { enabled: readAddress !== undefined },
  });
  const degenOwner = useReadContract({
    abi: degenDriverAbi,
    address: chainContracts.degenDriver,
    chainId: chain.id,
    functionName: "owner",
    query: { enabled: readAddress !== undefined },
  });
  const clockOwner = useReadContract({
    abi: demoDriverClockAbi,
    address: chainContracts.demoDriverClock,
    chainId: chain.id,
    functionName: "owner",
    query: { enabled: readAddress !== undefined },
  });
  const maxAdvance = useReadContract({
    abi: demoDriverClockAbi,
    address: chainContracts.demoDriverClock,
    chainId: chain.id,
    functionName: "MAX_ADVANCE",
    query: { enabled: onChain },
  });
  const epoch = useReadContract({
    abi: roundScheduleAbi,
    address: chainContracts.roundSchedule,
    chainId: chain.id,
    functionName: "i_epoch",
    query: { enabled: onChain },
  });
  const cruiseReady = useReadContract({
    abi: cruiseControlAbi,
    address: chainContracts.cruiseControl,
    chainId: chain.id,
    functionName: "harvestableRound",
    query: { enabled: onChain },
  });
  const degenReady = useReadContract({
    abi: degenDriverAbi,
    address: chainContracts.degenDriver,
    chainId: chain.id,
    functionName: "harvestableRound",
    query: { enabled: onChain },
  });

  const ownsCruise =
    readAddress !== undefined &&
    cruiseOwner.data !== undefined &&
    getAddress(cruiseOwner.data) === getAddress(readAddress);
  const ownsDegen =
    readAddress !== undefined &&
    degenOwner.data !== undefined &&
    getAddress(degenOwner.data) === getAddress(readAddress);
  const ownsClock =
    readAddress !== undefined &&
    clockOwner.data !== undefined &&
    getAddress(clockOwner.data) === getAddress(readAddress);

  const harvestCruise = useChainAction({
    abi: cruiseControlAbi,
    account: ownsCruise ? actionAddress : undefined,
    address: chainContracts.cruiseControl,
    args: [0n] as const,
    describeError,
    describeReceiptError,
    functionName: "harvest",
    scope: identity,
  });
  const harvestDegen = useChainAction({
    abi: degenDriverAbi,
    account: ownsDegen ? actionAddress : undefined,
    address: chainContracts.degenDriver,
    args: [0n] as const,
    describeError,
    describeReceiptError,
    functionName: "harvest",
    scope: identity,
  });
  const skip = useChainAction({
    abi: demoDriverClockAbi,
    account: ownsClock ? actionAddress : undefined,
    address: chainContracts.demoDriverClock,
    args: [epoch.data ?? 1n] as const,
    describeError,
    describeReceiptError,
    functionName: "advanceTime",
    scope: identity,
  });

  const view = ownerCardView({
    connected,
    onChain,
    ownsAny: ownsCruise || ownsDegen || ownsClock,
  });
  if (view === "hidden") {
    return null;
  }
  if (view === "switch") {
    return (
      <Card className="w-fit max-w-full self-center" title="Owner">
        <p className="text-sm text-ink-muted">
          {switchPrompt(chainLabel, "to harvest.")}
        </p>
      </Card>
    );
  }

  const busy = harvestCruise.busy || harvestDegen.busy || skip.busy;
  const skipTooLarge =
    epoch.data !== undefined &&
    maxAdvance.data !== undefined &&
    (epoch.data === 0n || epoch.data > maxAdvance.data);
  const skipLabel =
    epoch.data !== undefined && epoch.data % day === 0n
      ? `Skip ${epoch.data / day} days`
      : "Skip the round";

  async function onHarvest(
    fund: "1" | "2",
  ): Promise<void> {
    setNotice(undefined);
    setQuoteError(undefined);
    const abi = fund === "1" ? cruiseControlAbi : degenDriverAbi;
    const fundAddress =
      fund === "1" ? chainContracts.cruiseControl : chainContracts.degenDriver;
    const action = fund === "1" ? harvestCruise : harvestDegen;
    let plan: BuybackPlan;
    try {
      plan = await quoteHarvest(abi, fundAddress);
    } catch (error) {
      setQuoteError(describeError(error));
      return;
    }
    if (plan.status === "waiting") {
      return;
    }
    if (plan.status === "blocked") {
      setQuoteError("The buyback quote failed.");
      return;
    }
    const harvested = await action.send([plan.minDvrOut]);
    if (harvested) {
      setNotice(`Harvested Fund ${fund}.`);
    }
  }

  async function quoteHarvest(
    abi: typeof cruiseControlAbi | typeof degenDriverAbi,
    fundAddress: Address,
  ): Promise<BuybackPlan> {
    const heldRewards = await readContract(config, {
      abi,
      address: fundAddress,
      chainId: chain.id,
      functionName: "heldRewards",
    });
    const pendingRewards = await readContract(config, {
      abi,
      address: fundAddress,
      chainId: chain.id,
      functionName: "pendingRewards",
    });
    const pendingBuyback = await readContract(config, {
      abi,
      address: fundAddress,
      chainId: chain.id,
      functionName: "pendingBuyback",
    });
    const activeFarm = await readContract(config, {
      abi,
      address: fundAddress,
      chainId: chain.id,
      functionName: "activeFarm",
    });
    const hasActiveFarm = getAddress(activeFarm) !== zeroAddress;
    const rewardReserve = hasActiveFarm
      ? await readContract(config, {
          abi: mockFarmAbi,
          address: activeFarm,
          chainId: chain.id,
          functionName: "rewardReserve",
        })
      : 0n;
    const { half, spend } = buybackSpend({
      hasActiveFarm,
      heldRewards,
      pendingBuyback,
      pendingRewards,
      rewardReserve,
    });
    let quote: BuybackQuote = { status: "defer" };
    if (half !== 0n) {
      try {
        const quoted = await readContract(config, {
          abi: officialPoolAbi,
          address: chainContracts.officialPool,
          args: [0, spend],
          chainId: chain.id,
          functionName: "quoteExactInput",
        });
        quote = {
          status: "quoted",
          amountOut: quoted[0],
          usdcTax: quoted[1],
        };
      } catch (error) {
        if (deferredQuoteError(revertName(error))) {
          quote = { status: "defer" };
        } else {
          throw error;
        }
      }
    }
    return planBuyback({
      hasActiveFarm,
      heldRewards,
      pendingBuyback,
      pendingRewards,
      quote,
      rewardReserve,
    });
  }

  async function onSkip(): Promise<void> {
    if (epoch.data === undefined || skipTooLarge) {
      return;
    }
    setNotice(undefined);
    setQuoteError(undefined);
    const advanced = await skip.send([epoch.data]);
    if (advanced) {
      setNotice("Demo clock moved forward.");
    }
  }

  const errorMessage =
    quoteError ??
    harvestCruise.errorMessage ??
    harvestDegen.errorMessage ??
    skip.errorMessage;

  return (
    <Card className="w-fit max-w-full self-center" title="Owner">
      {chain.id === sepolia.id ? (
        <p className="text-sm text-ink-muted">
          A skip or a harvest on this demo clock is permanent.
        </p>
      ) : null}
      <StatList
        layout="inline"
        rows={[{ label: "Slippage", value: `${slippageBps / 100n}%` }]}
      />
      <div className="flex flex-wrap items-center gap-2">
        {ownsCruise ? (
          <button
            type="button"
            className={actionButtonClass()}
            disabled={busy || cruiseReady.data?.[0] !== true}
            onClick={() => {
              void onHarvest("1");
            }}
          >
            Harvest Fund 1
          </button>
        ) : null}
        {ownsDegen ? (
          <button
            type="button"
            className={actionButtonClass()}
            disabled={busy || degenReady.data?.[0] !== true}
            onClick={() => {
              void onHarvest("2");
            }}
          >
            Harvest Fund 2
          </button>
        ) : null}
        {ownsClock ? (
          <button
            type="button"
            className={actionButtonClass()}
            disabled={busy || epoch.data === undefined || skipTooLarge}
            onClick={() => {
              void onSkip();
            }}
          >
            {skipLabel}
          </button>
        ) : null}
      </div>
      {harvestCruise.simulating || harvestDegen.simulating || skip.simulating ? (
        <p className="text-sm text-ink-muted">Checking the transaction.</p>
      ) : null}
      {harvestCruise.writePending || harvestDegen.writePending || skip.writePending ? (
        <p className="text-sm text-ink-muted">Waiting for the wallet.</p>
      ) : null}
      {harvestCruise.confirming || harvestDegen.confirming ? (
        <p className="text-sm text-ink-muted">Confirming the harvest.</p>
      ) : null}
      {skip.confirming ? <p className="text-sm text-ink-muted">Confirming the clock skip.</p> : null}
      {notice && !busy ? <p className="text-sm text-ink-muted">{notice}</p> : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
    </Card>
  );
}
