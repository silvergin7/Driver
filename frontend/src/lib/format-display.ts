const maxFraction = 4;

export function formatDisplayAmount(value: bigint, decimals: number): string {
  if (value <= 0n || decimals < 0) {
    return "0";
  }
  const scale = 10n ** BigInt(decimals);
  const whole = value / scale;
  let fraction = value % scale;
  let places = decimals;
  if (places > maxFraction) {
    fraction /= 10n ** BigInt(places - maxFraction);
    places = maxFraction;
  }
  const trimmed =
    places === 0 ? "" : fraction.toString().padStart(places, "0").replace(/0+$/, "");
  const grouped = whole.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  if (trimmed.length === 0) {
    return whole === 0n ? "0" : grouped;
  }
  return `${grouped}.${trimmed}`;
}
