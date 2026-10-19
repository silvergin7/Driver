import { formatUnits } from "viem";

export function formatUsdc(value: bigint): string {
  const [whole = "0", fraction] = formatUnits(value, 6).split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const trimmed = fraction?.replace(/0+$/, "") ?? "";
  return trimmed.length > 0 ? `${grouped}.${trimmed}` : grouped;
}
