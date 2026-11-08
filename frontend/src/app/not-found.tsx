import Link from "next/link";
import { PageScene } from "@/components/page-scene";
import { actionButtonClass } from "@/lib/control-class";
import { notFoundCopy } from "@/lib/not-found-copy";

export default function NotFound() {
  return (
    <>
      <PageScene page="home" />
      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-6 px-6 pt-8 pb-12">
        <section className="flex flex-col items-center gap-6 text-center">
          <h1 className="text-4xl font-semibold tracking-tight text-brand-text">{notFoundCopy.title}</h1>
          <p className="text-lg text-ink">{notFoundCopy.text}</p>
          <div className="flex flex-wrap justify-center gap-3">
            <Link href="/" className={`${actionButtonClass()} inline-flex items-center`}>
              {notFoundCopy.home}
            </Link>
            <Link href="/simulation" className={`${actionButtonClass()} inline-flex items-center`}>
              {notFoundCopy.simulation}
            </Link>
          </div>
        </section>
      </main>
    </>
  );
}
