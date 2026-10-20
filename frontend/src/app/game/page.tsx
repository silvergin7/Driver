import { BalancesCard } from "@/components/balances-card";
import { LockVote } from "@/components/lock-vote";
import { OwnerControls } from "@/components/owner-controls";
import { PageScene } from "@/components/page-scene";
import { RoundChip } from "@/components/round-chip";
import { Treasury } from "@/components/treasury";

export default function GamePage() {
  return (
    <>
      <PageScene page="game" />
      <main className="mx-auto flex w-full max-w-5xl flex-col gap-8 px-6 pt-8 pb-16">
        <h1 className="text-center text-4xl font-semibold tracking-tight text-brand-text">
          Drive the treasury
        </h1>
        <RoundChip />
        <BalancesCard />
        <LockVote />
        <Treasury />
        <OwnerControls />
      </main>
    </>
  );
}
