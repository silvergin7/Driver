export function formatCountdown(target: bigint, now: bigint): string {
  const remaining = now >= target ? 0n : target - now;
  const hours = remaining / 3600n;
  const minutes = (remaining % 3600n) / 60n;
  const seconds = remaining % 60n;
  return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`;
}

function pad(value: bigint): string {
  const text = value.toString();
  return text.length >= 2 ? text : `0${text}`;
}
