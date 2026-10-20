import { FaucetsCard } from "@/components/faucets-card";
import { PageScene } from "@/components/page-scene";

export default function FaucetPage() {
  return (
    <>
      <PageScene page="faucet" />
      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-6 pt-8 pb-16">
        <h1 className="text-4xl font-semibold tracking-tight text-brand-text">Faucet</h1>
        <FaucetsCard />
      </main>
    </>
  );
}
