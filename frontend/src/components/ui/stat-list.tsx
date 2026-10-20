export function StatList({
  title,
  rows,
  layout = "spread",
}: {
  title?: string;
  rows: readonly { label: string; value: string }[];
  layout?: "spread" | "inline";
}) {
  const spread = layout === "spread";
  return (
    <div className="flex min-w-0 flex-col gap-2">
      {title !== undefined ? (
        <h3 className="text-sm font-semibold text-ink">{title}</h3>
      ) : null}
      <dl className="flex flex-col gap-2">
        {rows.map((row) => (
          <div
            key={row.label}
            className={
              spread
                ? "flex items-baseline justify-between gap-4"
                : "flex w-fit items-baseline gap-2"
            }
          >
            <dt className="text-sm text-ink-muted">{row.label}</dt>
            <dd
              className={
                spread
                  ? "min-w-0 text-right text-sm text-ink tabular-nums"
                  : "text-sm text-ink tabular-nums"
              }
            >
              {row.value}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
