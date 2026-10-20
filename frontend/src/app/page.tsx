import Link from "next/link";
import { ConnectWallet } from "@/components/connect-wallet";
import { PageScene } from "@/components/page-scene";
import { RoadSign } from "@/components/road-sign";
import { actionButtonClass } from "@/lib/control-class";

export default function Home() {
  return (
    <>
      <PageScene page="home" />
      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-12 px-6 pt-8 pb-12">
        <section className="flex flex-col items-center gap-6 text-center">
          <div>
            <h1 className="text-5xl font-semibold tracking-tight text-brand-text">Driver</h1>
            <p className="text-lg tracking-wide text-ink">DVR</p>
          </div>
          <p className="max-w-xl text-lg text-ink">
            The treasury is the student. You hold DVR, so you are the instructor.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-3">
            <Link
              href="/game"
              className={`${actionButtonClass()} inline-flex items-center`}
            >
              Drive the treasury
            </Link>
            <ConnectWallet compact />
          </div>
        </section>
        <section className="flex flex-col gap-4">
          <h2 className="text-2xl font-semibold text-ink">How it works</h2>
          <div aria-hidden="true" className="border-t-2 border-dashed border-line" />
          <ol className="grid gap-4 md:grid-cols-3">
            <RoadSign marker="1">The treasury is the student driver.</RoadSign>
            <RoadSign marker="2">
              Cruise Control never goes above 5%. Instructors vote each month on how
              fast Degen Driver may drive.
            </RoadSign>
            <RoadSign marker="3">
              Once a month the harvest is the driving test. What the car earned gets
              refuelled, and the rest burns DVR.
            </RoadSign>
          </ol>
        </section>
      </main>
    </>
  );
}
