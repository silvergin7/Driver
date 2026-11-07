import { PageScene } from "@/components/page-scene";
import { SimulationStepper } from "@/components/simulation-stepper";

export default function SimulationPage() {
  return (
    <>
      <PageScene page="simulation" />
      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-6 pt-8 pb-16">
        <div className="flex flex-col gap-3">
          <h1 className="text-4xl font-semibold tracking-tight text-brand-text">
            Simulation
          </h1>
          <p className="w-fit rounded-full border border-line px-3 py-1 text-sm text-ink">
            Simulation – nothing here is on-chain.
          </p>
        </div>
        <SimulationStepper />
      </main>
    </>
  );
}
