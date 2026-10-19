"use client";

import { useReadContracts } from "wagmi";
import { anvil, anvilNetworkLabel, contracts } from "@/config/contracts";
import {
  driverTokenAbi,
  officialPoolAbi,
  taxSplitterAbi,
} from "@/generated/contracts";
import { addressExplorer } from "@/lib/explorer";
import { burnedDvr } from "@/lib/burned-dvr";
import { formatBps } from "@/lib/format-bps";
import { formatDvr } from "@/lib/format-dvr";

const anvilContracts = contracts[anvil.id];

export function TokenFigures() {
  const figures = useReadContracts({
    allowFailure: false,
    contracts: [
      {
        abi: driverTokenAbi,
        address: anvilContracts.driverToken,
        chainId: anvil.id,
        functionName: "totalSupply",
      },
      {
        abi: driverTokenAbi,
        address: anvilContracts.driverToken,
        chainId: anvil.id,
        functionName: "MAX_SUPPLY",
      },
      {
        abi: driverTokenAbi,
        address: anvilContracts.driverToken,
        chainId: anvil.id,
        functionName: "totalMinted",
      },
      {
        abi: officialPoolAbi,
        address: anvilContracts.officialPool,
        chainId: anvil.id,
        functionName: "taxBps",
      },
      {
        abi: taxSplitterAbi,
        address: anvilContracts.taxSplitter,
        chainId: anvil.id,
        functionName: "FUND_1_BPS",
      },
      {
        abi: taxSplitterAbi,
        address: anvilContracts.taxSplitter,
        chainId: anvil.id,
        functionName: "FUND_2_BPS",
      },
      {
        abi: taxSplitterAbi,
        address: anvilContracts.taxSplitter,
        chainId: anvil.id,
        functionName: "FUND_3_BPS",
      },
    ],
  });
  const supply = bigintAt(figures.data, 0);
  const cap = bigintAt(figures.data, 1);
  const minted = bigintAt(figures.data, 2);
  const tax = bigintAt(figures.data, 3);
  const fund1 = bigintAt(figures.data, 4);
  const fund2 = bigintAt(figures.data, 5);
  const fund3 = bigintAt(figures.data, 6);
  const burned =
    minted !== undefined && supply !== undefined
      ? burnedDvr(minted, supply)
      : undefined;
  const explorer = addressExplorer(anvil, anvilContracts.driverToken);
  const failed = figures.isError && figures.data === undefined;

  return (
    <div className="flex max-w-3xl flex-col gap-8">
      <dl className="grid gap-4">
        <Figure label="Total supply" value={dvrFigure(supply, failed, figures.isFetched)} />
        <Figure label="Lifetime cap" value={dvrFigure(cap, failed, figures.isFetched)} />
        <Figure label="Total DVR burned" value={burnedFigure(burned, minted, supply, failed, figures.isFetched)} />
        <Figure label="Buy and sell tax" value={bpsFigure(tax, failed, figures.isFetched)} />
        <div>
          <dt className="text-ink-muted">Tax split</dt>
          <dd className="tabular-nums text-ink">
            {fund1 !== undefined && fund2 !== undefined && fund3 !== undefined
              ? `Fund 1 ${formatBps(fund1)}, Fund 2 ${formatBps(fund2)}, Fund 3 ${formatBps(fund3)}`
              : failed
                ? "Unavailable."
                : "Loading…"}
          </dd>
        </div>
        <div>
          <dt className="text-ink-muted">Token contract</dt>
          <dd className="break-all font-mono text-sm text-ink">
            {anvilContracts.driverToken}
          </dd>
        </div>
        <div>
          <dt className="text-ink-muted">Network</dt>
          <dd className="text-ink">{anvilNetworkLabel}</dd>
        </div>
        <div>
          <dt className="text-ink-muted">Explorer</dt>
          <dd>
            {explorer.kind === "local" ? (
              <span className="text-ink">Local network</span>
            ) : (
              <a
                className="text-sign underline"
                href={explorer.href}
                target="_blank"
                rel="noreferrer"
              >
                View on {explorer.name}
              </a>
            )}
          </dd>
        </div>
      </dl>
      <section className="flex flex-col gap-3 text-ink">
        <h2 className="text-2xl font-semibold">Tokenomics</h2>
        <p>The lifetime cap is 1,000,000 DVR.</p>
        <ul className="list-disc pl-5">
          <li>Official pool liquidity, locked: 500,000 DVR.</li>
          <li>DVR faucet: 50,000 DVR.</li>
          <li>Community reward pool: 300,000 DVR.</li>
          <li>Team reserve: 150,000 DVR.</li>
        </ul>
        <p>
          The 300,000 community DVR and the 150,000 team DVR are held by the
          deployer until their contracts exist.
        </p>
        <p>Buys and sells pay the tax in mUSDC.</p>
        <p>Fund 3&apos;s 20% stays in the splitter until Fund 3 exists.</p>
        <p>
          Half of a fund&apos;s rewards is put back into the farm. Half buys DVR
          from the official pool and burns it.
        </p>
      </section>
    </div>
  );
}

function Figure({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-ink-muted">{label}</dt>
      <dd className="tabular-nums text-ink">{value}</dd>
    </div>
  );
}

function burnedFigure(
  burned: bigint | undefined,
  minted: bigint | undefined,
  supply: bigint | undefined,
  failed: boolean,
  fetched: boolean,
): string {
  if (minted !== undefined && supply !== undefined) {
    return burned === undefined ? "Unavailable." : `${formatDvr(burned)} DVR`;
  }
  return dvrFigure(undefined, failed, fetched);
}

function dvrFigure(
  value: bigint | undefined,
  failed: boolean,
  fetched: boolean,
): string {
  if (value !== undefined) {
    return `${formatDvr(value)} DVR`;
  }
  if (failed || fetched) {
    return "Unavailable.";
  }
  return "Loading…";
}

function bpsFigure(
  value: bigint | undefined,
  failed: boolean,
  fetched: boolean,
): string {
  if (value !== undefined) {
    return formatBps(value);
  }
  if (failed || fetched) {
    return "Unavailable.";
  }
  return "Loading…";
}

function bigintAt(
  data: readonly unknown[] | undefined,
  index: number,
): bigint | undefined {
  const value = data?.[index];
  return typeof value === "bigint" ? value : undefined;
}
