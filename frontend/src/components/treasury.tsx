"use client";

import { getAddress, isAddress, zeroAddress, type Address } from "viem";
import { useConnection, useReadContract, useReadContracts } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import {
  cruiseControlAbi,
  degenDriverAbi,
  demoDriverClockAbi,
  driverTokenAbi,
  driverVoteAbi,
  mockFarmAbi,
  roundScheduleAbi,
} from "@/generated/contracts";
import { formatCountdown } from "@/lib/countdown";
import { farmLabel } from "@/lib/farm-label";
import { formatDvr } from "@/lib/format-dvr";
import { formatUsdc } from "@/lib/format-usdc";

const anvilContracts = contracts[anvil.id];

export function Treasury() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const cruiseCalls = fundCalls(cruiseControlAbi, anvilContracts.cruiseControl);
  const degenCalls = fundCalls(degenDriverAbi, anvilContracts.degenDriver);
  const cruise = useReadContracts({
    allowFailure: false,
    contracts: cruiseCalls,
    query: { enabled: onAnvil },
  });
  const degen = useReadContracts({
    allowFailure: false,
    contracts: degenCalls,
    query: { enabled: onAnvil },
  });
  const cruiseFarm = fundAddress(cruise.data?.[3]);
  const degenFarm = fundAddress(degen.data?.[3]);
  const cruiseApr = useReadContract({
    abi: mockFarmAbi,
    address: cruiseFarm ?? zeroAddress,
    chainId: anvil.id,
    functionName: "aprBps",
    query: { enabled: cruiseFarm !== undefined && cruiseFarm !== zeroAddress },
  });
  const degenApr = useReadContract({
    abi: mockFarmAbi,
    address: degenFarm ?? zeroAddress,
    chainId: anvil.id,
    functionName: "aprBps",
    query: { enabled: degenFarm !== undefined && degenFarm !== zeroAddress },
  });
  const round = useReadContract({
    abi: roundScheduleAbi,
    address: anvilContracts.roundSchedule,
    chainId: anvil.id,
    functionName: "currentRound",
    query: { enabled: onAnvil },
  });
  const roundEnd = useReadContract({
    abi: driverVoteAbi,
    address: anvilContracts.driverVote,
    chainId: anvil.id,
    functionName: "openRoundEnd",
    query: { enabled: onAnvil },
  });
  const clock = useReadContract({
    abi: demoDriverClockAbi,
    address: anvilContracts.demoDriverClock,
    chainId: anvil.id,
    functionName: "currentTime",
    query: { enabled: onAnvil },
  });
  const minted = useReadContract({
    abi: driverTokenAbi,
    address: anvilContracts.driverToken,
    chainId: anvil.id,
    functionName: "totalMinted",
    query: { enabled: onAnvil },
  });
  const supply = useReadContract({
    abi: driverTokenAbi,
    address: anvilContracts.driverToken,
    chainId: anvil.id,
    functionName: "totalSupply",
    query: { enabled: onAnvil },
  });

  if (!connection.isConnected) {
    return (
      <section className="text-left">
        <h2 className="text-xl font-semibold">Treasury</h2>
        <p>Connect a wallet to see the funds.</p>
      </section>
    );
  }
  if (!onAnvil) {
    return (
      <section className="text-left">
        <h2 className="text-xl font-semibold">Treasury</h2>
        <p>Switch to Anvil to see the funds.</p>
      </section>
    );
  }

  const failed =
    unread(cruise) ||
    unread(degen) ||
    unread(round) ||
    unread(roundEnd) ||
    unread(clock) ||
    unread(minted) ||
    unread(supply) ||
    unread(cruiseApr) ||
    unread(degenApr);
  const ready =
    cruise.data !== undefined &&
    degen.data !== undefined &&
    round.data !== undefined &&
    roundEnd.data !== undefined &&
    clock.data !== undefined &&
    minted.data !== undefined &&
    supply.data !== undefined &&
    (cruiseFarm === undefined ||
      cruiseFarm === zeroAddress ||
      cruiseApr.data !== undefined) &&
    (degenFarm === undefined ||
      degenFarm === zeroAddress ||
      degenApr.data !== undefined);

  const boughtBack =
    typeof cruise.data?.[5] === "bigint" && typeof degen.data?.[5] === "bigint"
      ? cruise.data[5] + degen.data[5]
      : undefined;
  const totalBurned =
    minted.data !== undefined && supply.data !== undefined
      ? minted.data - supply.data
      : undefined;

  return (
    <section className="flex w-full flex-col gap-3 text-left">
      <h2 className="text-xl font-semibold">Treasury</h2>
      {failed ? <p>Fund status unavailable.</p> : null}
      {!failed && !ready ? <p>Loading funds…</p> : null}
      {ready &&
      clock.data !== undefined &&
      round.data !== undefined &&
      roundEnd.data !== undefined ? (
        <p className="tabular-nums">
          Demo clock. Round {round.data.toString()} ends in{" "}
          {formatCountdown(roundEnd.data, clock.data)}.
        </p>
      ) : null}
      <FundSummary
        apr={cruiseApr.data}
        data={cruise.data}
        farm={cruiseFarm}
        title="Fund 1"
      />
      <FundSummary
        apr={degenApr.data}
        data={degen.data}
        farm={degenFarm}
        title="Fund 2"
      />
      {boughtBack !== undefined ? (
        <p className="tabular-nums">
          Bought back and burned: {formatDvr(boughtBack)} DVR
        </p>
      ) : null}
      {totalBurned !== undefined ? (
        <p className="tabular-nums">
          Total DVR burned: {formatDvr(totalBurned)} DVR
        </p>
      ) : null}
    </section>
  );
}

function FundSummary({
  title,
  data,
  farm,
  apr,
}: {
  title: string;
  data: readonly unknown[] | undefined;
  farm: Address | undefined;
  apr: bigint | undefined;
}) {
  const value = typeof data?.[0] === "bigint" ? data[0] : undefined;
  const idle = typeof data?.[1] === "bigint" ? data[1] : undefined;
  const principal = typeof data?.[2] === "bigint" ? data[2] : undefined;
  const pending = typeof data?.[4] === "bigint" ? data[4] : undefined;
  if (
    value === undefined ||
    idle === undefined ||
    principal === undefined ||
    pending === undefined ||
    farm === undefined
  ) {
    return null;
  }
  const farmName =
    farm === zeroAddress
      ? "No active farm"
      : apr === undefined
        ? farm
        : farmLabel(apr, farm);
  return (
    <div className="flex flex-col gap-1">
      <h3 className="font-semibold">{title}</h3>
      <p className="tabular-nums">Value: {formatUsdc(value)} mUSDC</p>
      <p className="tabular-nums">Idle: {formatUsdc(idle)} mUSDC</p>
      <p className="tabular-nums">Principal: {formatUsdc(principal)} mUSDC</p>
      <p>Active farm: {farmName}</p>
      <p className="tabular-nums">Pending rewards: {formatUsdc(pending)} mUSDC</p>
    </div>
  );
}

function fundCalls(
  abi: typeof cruiseControlAbi | typeof degenDriverAbi,
  address: Address,
) {
  return [
    viewCall(abi, address, "value"),
    viewCall(abi, address, "idle"),
    viewCall(abi, address, "principal"),
    viewCall(abi, address, "activeFarm"),
    viewCall(abi, address, "pendingRewards"),
    viewCall(abi, address, "dvrBoughtBack"),
  ] as const;
}

function viewCall(
  abi: typeof cruiseControlAbi | typeof degenDriverAbi,
  address: Address,
  functionName:
    | "value"
    | "idle"
    | "principal"
    | "activeFarm"
    | "pendingRewards"
    | "dvrBoughtBack",
) {
  return {
    abi,
    address,
    chainId: anvil.id,
    functionName,
  };
}

function fundAddress(value: unknown): Address | undefined {
  return typeof value === "string" && isAddress(value) ? getAddress(value) : undefined;
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}
