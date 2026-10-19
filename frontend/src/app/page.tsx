import { ClaimTokens } from "@/components/claim-tokens";
import { ClaimUsdc } from "@/components/claim-usdc";
import { LockVote } from "@/components/lock-vote";
import { Treasury } from "@/components/treasury";
import { DvrBalance } from "@/components/dvr-balance";
import { UsdcBalance } from "@/components/usdc-balance";
import { WalletStatus } from "@/components/wallet-status";

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-lg flex-1 flex-col gap-6 px-6 py-16">
      <header className="text-center">
        <h1 className="text-4xl font-semibold tracking-tight">Driver</h1>
        <p className="text-lg tracking-wide">DVR</p>
      </header>
      <WalletStatus />
      <DvrBalance />
      <UsdcBalance />
      <ClaimTokens />
      <ClaimUsdc />
      <LockVote />
      <Treasury />
    </main>
  );
}
