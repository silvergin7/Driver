import { PageScene } from "@/components/page-scene";
import { TokenFigures } from "@/components/token-figures";

export default function TokenPage() {
  return (
    <>
      <PageScene page="token" />
      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-8 px-6 pt-8 pb-12">
        <h1 className="text-4xl font-semibold tracking-tight text-brand-text">Token</h1>
        <TokenFigures />
      </main>
    </>
  );
}
