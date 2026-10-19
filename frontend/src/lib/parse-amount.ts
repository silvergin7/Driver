import { parseUnits } from "viem";

export type ParsedAmount =
  | { status: "empty" }
  | { status: "invalid" }
  | { status: "zero" }
  | { status: "amount"; amount: bigint };

export function parseTokenAmount(
  text: string,
  decimals: number,
): ParsedAmount {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return { status: "empty" };
  }
  if (!/^\d+(\.\d+)?$/.test(trimmed)) {
    return { status: "invalid" };
  }
  const fraction = trimmed.split(".")[1] ?? "";
  if (fraction.length > decimals) {
    return { status: "invalid" };
  }
  try {
    const amount = parseUnits(trimmed, decimals);
    if (amount === 0n) {
      return { status: "zero" };
    }
    return { status: "amount", amount };
  } catch {
    return { status: "invalid" };
  }
}
