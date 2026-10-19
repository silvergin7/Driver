import type { ReactNode } from "react";

export function RoadSign({
  marker,
  children,
}: {
  marker: string;
  children: ReactNode;
}) {
  return (
    <li className="rounded-xl border-2 border-sign bg-background p-4 text-left text-ink shadow-raise">
      <p className="text-2xl font-semibold text-brand-text">{marker}</p>
      <p className="mt-2">{children}</p>
    </li>
  );
}
