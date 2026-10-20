import type { ReactNode } from "react";

export function Badge({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex w-fit max-w-full self-start rounded-full border border-line px-2.5 py-0.5 text-sm text-ink">
      {children}
    </span>
  );
}
