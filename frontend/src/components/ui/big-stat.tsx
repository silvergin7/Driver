export function BigStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <p className="text-sm text-ink-muted">{label}</p>
      <p className="text-2xl font-semibold break-all text-ink tabular-nums">{value}</p>
    </div>
  );
}
