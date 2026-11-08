import { CountUp } from "@/components/count-up";

export function BigStat({
  label,
  value,
  count = false,
}: {
  label: string;
  value: string;
  count?: boolean;
}) {
  const className = "text-2xl font-semibold break-all text-ink tabular-nums";
  return (
    <div className="min-w-0">
      <p className="text-sm text-ink-muted">{label}</p>
      {count ? (
        <CountUp value={value} className={className} />
      ) : (
        <p className={className}>{value}</p>
      )}
    </div>
  );
}
