import Link from "next/link";
import { ConnectWallet } from "@/components/connect-wallet";
import { PageScene } from "@/components/page-scene";
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
            <Link
              href="/simulation"
              className={`${actionButtonClass()} inline-flex items-center`}
            >
              How it works
            </Link>
            <ConnectWallet compact />
          </div>
        </section>
      </main>
    </>
  );
}
