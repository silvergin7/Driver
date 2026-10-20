import { PageScene } from "@/components/page-scene";
import { DvrBalance } from "@/components/dvr-balance";
import { LockVote } from "@/components/lock-vote";
import { OwnerControls } from "@/components/owner-controls";
import { Treasury } from "@/components/treasury";
import { UsdcBalance } from "@/components/usdc-balance";
import { WalletStatus } from "@/components/wallet-status";

export default function GamePage() {
  return (
    <>
      <PageScene page="game" />
      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-6 pt-8 pb-16">
        <h1 className="text-4xl font-semibold tracking-tight text-brand-text">
          Drive the treasury
        </h1>
        <section className="flex flex-col gap-8">
          <h2 className="text-2xl font-semibold text-ink">Wallet</h2>
          <WalletStatus />
          <DvrBalance />
          <UsdcBalance />
        </section>
        <div className="flex flex-col gap-4">
          <p>Instructors vote on Degen Driver&apos;s speed.</p>
          <LockVote />
        </div>
        <div className="flex flex-col gap-4">
          <p>
            Cruise Control never goes above 5%. Degen Driver drives as fast as the
            instructors allow.
          </p>
          <Treasury />
        </div>
        <OwnerControls />
      </main>
    </>
  );
}
