import { formatUnits } from "viem";

export function maxAmountText(value: bigint, decimals: number): string {
  const [whole = "0", fraction] = formatUnits(value, decimals).split(".");
  const trimmed = fraction?.replace(/0+$/, "") ?? "";
  return trimmed.length > 0 ? `${whole}.${trimmed}` : whole;
}
