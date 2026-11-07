import type { ReactNode } from "react";

export function RoadSign({
  marker,
  done = false,
  children,
}: {
  marker: string;
  done?: boolean;
  children: ReactNode;
}) {
  const number = <p className="text-2xl font-semibold text-brand-text">{marker}</p>;
  return (
    <li className="rounded-xl border-2 border-sign bg-background p-4 text-left text-ink shadow-raise">
      {done ? (
        <div className="flex items-baseline justify-between gap-4">
          {number}
          <p className="text-sm font-semibold text-ink">Done</p>
        </div>
      ) : (
        number
      )}
      <p className="mt-2">{children}</p>
    </li>
  );
}
