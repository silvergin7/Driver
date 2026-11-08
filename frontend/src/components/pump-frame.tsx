import type { ReactNode } from "react";

export const readoutClass = "rounded-lg bg-[#0f172a] p-4 text-slate-50";

export function Pump({
  title,
  bandClass,
  children,
}: {
  title: ReactNode;
  bandClass: string;
  children: ReactNode;
}) {
  return (
    <section className="relative flex h-full min-w-0 flex-col overflow-hidden rounded-2xl border-2 border-line bg-surface shadow-raise">
      <h2
        className={`flex items-center gap-2 rounded-t-2xl px-4 py-3 text-lg font-semibold text-white ${bandClass}`}
      >
        {title}
      </h2>
      <div className="relative flex flex-1 flex-col gap-4 p-4 sm:pr-16">
        {children}
        <Nozzle />
      </div>
    </section>
  );
}

function Nozzle() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 48 120"
      className="pointer-events-none absolute top-4 right-2 hidden h-28 w-10 text-ink sm:block"
    >
      <path
        d="M14 4h8v34c0 12 16 12 16 26v24"
        fill="none"
        stroke="currentColor"
        strokeWidth="4"
        strokeLinecap="round"
      />
      <rect x="28" y="86" width="16" height="14" rx="3" fill="currentColor" />
      <path d="M36 100v12" stroke="currentColor" strokeWidth="4" strokeLinecap="round" />
    </svg>
  );
}
