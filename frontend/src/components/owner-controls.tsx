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
import { useConfig, useConnection, useReadContract } from "wagmi";
import { readContract } from "wagmi/actions";
import { anvil, contracts } from "@/config/contracts";
import {
  cruiseControlAbi,
  degenDriverAbi,
  demoDriverClockAbi,
  mockFarmAbi,
  officialPoolAbi,
  roundScheduleAbi,
} from "@/generated/contracts";
import { useAnvilAction } from "@/hooks/use-anvil-action";
import {
  actionErrorMessage,
  actionReceiptErrorMessage,
} from "@/lib/action-errors";
import { actionButtonClass, headingClass, sectionClass } from "@/lib/control-class";
import {
  buybackSpend,
  deferredQuoteError,
  planBuyback,
  type BuybackPlan,
  type BuybackQuote,
} from "@/lib/buyback-quote";
import { slippageBps } from "@/lib/slippage";

const anvilContracts = contracts[anvil.id];
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
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const address = onAnvil ? connection.address : undefined;
  const identity = `${address ?? "disconnected"}:${connection.chainId ?? "none"}`;
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
    address: anvilContracts.cruiseControl,
    chainId: anvil.id,
    functionName: "owner",
    query: { enabled: address !== undefined },
  });
  const degenOwner = useReadContract({
    abi: degenDriverAbi,
    address: anvilContracts.degenDriver,
    chainId: anvil.id,
    functionName: "owner",
    query: { enabled: address !== undefined },
  });
  const clockOwner = useReadContract({
    abi: demoDriverClockAbi,
    address: anvilContracts.demoDriverClock,
    chainId: anvil.id,
    functionName: "owner",
    query: { enabled: address !== undefined },
  });
  const maxAdvance = useReadContract({
    abi: demoDriverClockAbi,
    address: anvilContracts.demoDriverClock,
    chainId: anvil.id,
    functionName: "MAX_ADVANCE",
    query: { enabled: onAnvil },
  });
  const epoch = useReadContract({
    abi: roundScheduleAbi,
    address: anvilContracts.roundSchedule,
    chainId: anvil.id,
    functionName: "i_epoch",
    query: { enabled: onAnvil },
  });
  const cruiseReady = useReadContract({
    abi: cruiseControlAbi,
    address: anvilContracts.cruiseControl,
    chainId: anvil.id,
    functionName: "harvestableRound",
    query: { enabled: onAnvil },
  });
  const degenReady = useReadContract({
    abi: degenDriverAbi,
    address: anvilContracts.degenDriver,
    chainId: anvil.id,
    functionName: "harvestableRound",
    query: { enabled: onAnvil },
  });

  const ownsCruise =
    address !== undefined &&
    cruiseOwner.data !== undefined &&
    getAddress(cruiseOwner.data) === getAddress(address);
  const ownsDegen =
    address !== undefined &&
    degenOwner.data !== undefined &&
    getAddress(degenOwner.data) === getAddress(address);
  const ownsClock =
    address !== undefined &&
    clockOwner.data !== undefined &&
    getAddress(clockOwner.data) === getAddress(address);

  const harvestCruise = useAnvilAction({
    abi: cruiseControlAbi,
    account: ownsCruise ? address : undefined,
    address: anvilContracts.cruiseControl,
    args: [0n] as const,
    describeError,
    describeReceiptError,
    functionName: "harvest",
    scope: identity,
  });
  const harvestDegen = useAnvilAction({
    abi: degenDriverAbi,
    account: ownsDegen ? address : undefined,
    address: anvilContracts.degenDriver,
    args: [0n] as const,
    describeError,
    describeReceiptError,
    functionName: "harvest",
    scope: identity,
  });
  const skip = useAnvilAction({
    abi: demoDriverClockAbi,
    account: ownsClock ? address : undefined,
    address: anvilContracts.demoDriverClock,
    args: [epoch.data ?? 1n] as const,
    describeError,
    describeReceiptError,
    functionName: "advanceTime",
    scope: identity,
  });

  if (connection.isConnected && !onAnvil) {
    return (
      <section className={sectionClass()}>
        <h2 className={headingClass()}>Owner</h2>
        <p>Switch to Anvil to harvest.</p>
      </section>
    );
  }
  if (!ownsCruise && !ownsDegen && !ownsClock) {
    return null;
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
      fund === "1" ? anvilContracts.cruiseControl : anvilContracts.degenDriver;
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
      chainId: anvil.id,
      functionName: "heldRewards",
    });
    const pendingRewards = await readContract(config, {
      abi,
      address: fundAddress,
      chainId: anvil.id,
      functionName: "pendingRewards",
    });
    const pendingBuyback = await readContract(config, {
      abi,
      address: fundAddress,
      chainId: anvil.id,
      functionName: "pendingBuyback",
    });
    const activeFarm = await readContract(config, {
      abi,
      address: fundAddress,
      chainId: anvil.id,
      functionName: "activeFarm",
    });
    const hasActiveFarm = getAddress(activeFarm) !== zeroAddress;
    const rewardReserve = hasActiveFarm
      ? await readContract(config, {
          abi: mockFarmAbi,
          address: activeFarm,
          chainId: anvil.id,
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
          address: anvilContracts.officialPool,
          args: [0, spend],
          chainId: anvil.id,
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
    <section className={sectionClass()}>
      <h2 className={headingClass()}>Owner</h2>
      <p>Slippage {slippageBps / 100n}%</p>
      <div className="flex flex-wrap gap-2">
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
        <p>Checking the transaction.</p>
      ) : null}
      {harvestCruise.writePending || harvestDegen.writePending || skip.writePending ? (
        <p>Waiting for the wallet.</p>
      ) : null}
      {harvestCruise.confirming || harvestDegen.confirming ? (
        <p>Confirming the harvest.</p>
      ) : null}
      {skip.confirming ? <p>Confirming the clock skip.</p> : null}
      {notice && !busy ? <p>{notice}</p> : null}
      {errorMessage ? <p role="alert">{errorMessage}</p> : null}
    </section>
  );
}
