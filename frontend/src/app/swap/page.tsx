import { PageScene } from "@/components/page-scene";
import { PoolSwap } from "@/components/pool-swap";

export default function SwapPage() {
  return (
    <>
      <PageScene page="swap" />
      <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-8 px-6 pt-8 pb-16">
        <h1 className="text-4xl font-semibold tracking-tight text-brand-text">Swap</h1>
        <PoolSwap />
      </main>
    </>
  );
}
