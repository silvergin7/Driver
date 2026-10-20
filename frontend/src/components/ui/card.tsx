import type { ReactNode } from "react";

export function Card({
  title,
  subtitle,
  children,
  className = "",
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`flex h-full min-w-0 flex-col gap-4 rounded-xl bg-surface p-4 text-left ${className}`}
    >
      <div className="flex flex-col gap-1">
        <h2 className="text-xl font-semibold text-ink">{title}</h2>
        {subtitle !== undefined ? (
          <p className="text-sm text-ink-muted">{subtitle}</p>
        ) : null}
      </div>
      {children}
    </section>
  );
}
