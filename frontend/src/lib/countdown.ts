const minute = 60n;
const hour = 60n * minute;
const day = 24n * hour;

export function formatCountdown(target: bigint, now: bigint): string {
  const remaining = now >= target ? 0n : target - now;
  if (remaining < minute) {
    return "less than a minute";
  }
  const totalMinutes = remaining / minute;
  const days = totalMinutes / (day / minute);
  const hours = (totalMinutes / (hour / minute)) % 24n;
  const minutes = totalMinutes % 60n;
  return [unit(days, "day", "days"), unit(hours, "hour", "hours"), unit(minutes, "minute", "minutes")]
    .filter((part): part is string => part !== undefined)
    .join(" ");
}

function unit(count: bigint, singular: string, plural: string): string | undefined {
  if (count === 0n) {
    return undefined;
  }
  return `${count.toString()} ${count === 1n ? singular : plural}`;
}
