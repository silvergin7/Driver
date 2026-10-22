"use client";

import { getAddress, isAddress, zeroAddress, type Address } from "viem";
import { useConnection, useReadContract, useReadContracts } from "wagmi";
import { chain, chainLabel, contracts } from "@/config/contracts";
import { switchPrompt } from "@/lib/switch-prompt";
import {
  cruiseControlAbi,
  degenDriverAbi,
  driverTokenAbi,
  mockFarmAbi,
} from "@/generated/contracts";
import { burnedDvr } from "@/lib/burned-dvr";
import { farmLabel } from "@/lib/farm-label";
import { formatBps } from "@/lib/format-bps";
import { formatDvr } from "@/lib/format-dvr";
import { formatUsdc } from "@/lib/format-usdc";
import { farmAprBps } from "@/lib/farm-apr";
import { Badge } from "@/components/ui/badge";
import { BigStat } from "@/components/ui/big-stat";
import { Card } from "@/components/ui/card";
import { StatList } from "@/components/ui/stat-list";

const chainContracts = contracts[chain.id];

const treasurySubtitle =
  "Cruise Control never goes above 5%. Degen Driver drives as fast as the instructors allow.";

export function Treasury() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const cruiseCalls = fundCalls(cruiseControlAbi, chainContracts.cruiseControl);
  const degenCalls = fundCalls(degenDriverAbi, chainContracts.degenDriver);
  const cruise = useReadContracts({
    allowFailure: false,
    contracts: cruiseCalls,
    query: { enabled: onChain },
  });
  const degen = useReadContracts({
    allowFailure: false,
    contracts: degenCalls,
    query: { enabled: onChain },
  });
  const cruiseFarm = fundAddress(cruise.data?.[3]);
  const degenFarm = fundAddress(degen.data?.[3]);
  const cruiseFarmState = useFarmState(cruiseFarm);
  const degenFarmState = useFarmState(degenFarm);
  const minted = useReadContract({
    abi: driverTokenAbi,
    address: chainContracts.driverToken,
    chainId: chain.id,
    functionName: "totalMinted",
    query: { enabled: onChain },
  });
  const supply = useReadContract({
    abi: driverTokenAbi,
    address: chainContracts.driverToken,
    chainId: chain.id,
    functionName: "totalSupply",
    query: { enabled: onChain },
  });

  if (!connection.isConnected) {
    return (
      <Card className="w-full" title="Treasury" subtitle={treasurySubtitle}>
        <p className="text-sm text-ink-muted">Connect a wallet to see the funds.</p>
      </Card>
    );
  }
  if (!onChain) {
    return (
      <Card className="w-full" title="Treasury" subtitle={treasurySubtitle}>
        <p className="text-sm text-ink-muted">
          {switchPrompt(chainLabel, "to see the funds.")}
        </p>
      </Card>
    );
  }

  const failed =
    unread(cruise) ||
    unread(degen) ||
    unread(minted) ||
    unread(supply) ||
    unread(cruiseFarmState.apr) ||
    unread(cruiseFarmState.paused) ||
    unread(cruiseFarmState.reserve) ||
    unread(degenFarmState.apr) ||
    unread(degenFarmState.paused) ||
    unread(degenFarmState.reserve);
  const ready =
    cruise.data !== undefined &&
    degen.data !== undefined &&
    minted.data !== undefined &&
    supply.data !== undefined &&
    farmStateReady(cruiseFarm, cruiseFarmState) &&
    farmStateReady(degenFarm, degenFarmState);

  const boughtBack =
    typeof cruise.data?.[5] === "bigint" && typeof degen.data?.[5] === "bigint"
      ? cruise.data[5] + degen.data[5]
      : undefined;
  const totalBurned =
    minted.data !== undefined && supply.data !== undefined
      ? burnedDvr(minted.data, supply.data)
      : undefined;

  const burnedRows = [
    boughtBack !== undefined
      ? { label: "Bought back and burned", value: `${formatDvr(boughtBack)} DVR` }
      : undefined,
    totalBurned !== undefined
      ? { label: "Total DVR burned", value: `${formatDvr(totalBurned)} DVR` }
      : undefined,
  ].filter((row): row is { label: string; value: string } => row !== undefined);

  return (
    <Card className="w-full" title="Treasury" subtitle={treasurySubtitle}>
      {failed ? <p className="text-sm text-ink-muted">Fund status unavailable.</p> : null}
      {!failed && !ready ? <p className="text-sm text-ink-muted">Loading funds…</p> : null}
      <div className="grid gap-6 md:grid-cols-2 md:items-stretch">
        <FundSummary
          data={cruise.data}
          farm={cruiseFarm}
          state={cruiseFarmState}
          title="Fund 1"
        />
        <FundSummary
          data={degen.data}
          farm={degenFarm}
          state={degenFarmState}
          title="Fund 2"
        />
      </div>
      {burnedRows.length > 0 ? <StatList rows={burnedRows} /> : null}
      {ready ? (
        <p className="text-sm text-ink-muted">
          APR is simple interest. At each harvest, half of the rewards goes back into the farm.
        </p>
      ) : null}
    </Card>
  );
}

function useFarmState(farm: Address | undefined) {
  const enabled = farm !== undefined && farm !== zeroAddress;
  const address = farm ?? zeroAddress;
  const apr = useReadContract({
    abi: mockFarmAbi,
    address,
    chainId: chain.id,
    functionName: "aprBps",
    query: { enabled },
  });
  const paused = useReadContract({
    abi: mockFarmAbi,
    address,
    chainId: chain.id,
    functionName: "paused",
    query: { enabled },
  });
  const reserve = useReadContract({
    abi: mockFarmAbi,
    address,
    chainId: chain.id,
    functionName: "rewardReserve",
    query: { enabled },
  });
  return { apr, paused, reserve };
}

function farmStateReady(
  farm: Address | undefined,
  state: ReturnType<typeof useFarmState>,
): boolean {
  if (farm === undefined || farm === zeroAddress) {
    return true;
  }
  return (
    state.apr.data !== undefined &&
    state.paused.data !== undefined &&
    state.reserve.data !== undefined
  );
}

function FundSummary({
  title,
  data,
  farm,
  state,
}: {
  title: string;
  data: readonly unknown[] | undefined;
  farm: Address | undefined;
  state: ReturnType<typeof useFarmState>;
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
  const active = farm !== zeroAddress;
  if (
    active &&
    (state.apr.data === undefined ||
      state.paused.data === undefined ||
      state.reserve.data === undefined)
  ) {
    return null;
  }
  const farmApr = farmAprBps({
    aprBps: state.apr.data ?? 0n,
    active,
    paused: state.paused.data === true,
    rewardReserve: state.reserve.data ?? 0n,
  });
  const farmName = active
    ? state.apr.data === undefined
      ? farm
      : farmLabel(state.apr.data, farm)
    : "No active farm";
  return (
    <div className="flex h-full min-w-0 flex-col gap-3">
      <h3 className="font-semibold text-ink">{title}</h3>
      <Badge>
        {active ? `${farmName} · ${formatBps(farmApr)} APR` : "No active farm"}
      </Badge>
      <BigStat label="Value" value={`${formatUsdc(value)} mUSDC`} />
      <StatList
        rows={[
          { label: "Idle", value: `${formatUsdc(idle)} mUSDC` },
          { label: "Principal", value: `${formatUsdc(principal)} mUSDC` },
          { label: "Pending rewards", value: `${formatUsdc(pending)} mUSDC` },
        ]}
      />
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
    chainId: chain.id,
    functionName,
  };
}

function fundAddress(value: unknown): Address | undefined {
  return typeof value === "string" && isAddress(value) ? getAddress(value) : undefined;
}

function unread(read: { isError: boolean; data: unknown }): boolean {
  return read.isError && read.data === undefined;
}
