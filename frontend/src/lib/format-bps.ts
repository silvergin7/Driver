export function formatBps(bps: bigint): string {
  const whole = bps / 100n;
  const fraction = bps % 100n;
  if (fraction === 0n) {
    return `${whole.toString()}%`;
  }
  const digits = fraction.toString().padStart(2, "0").replace(/0+$/, "");
  return `${whole.toString()}.${digits}%`;
}
