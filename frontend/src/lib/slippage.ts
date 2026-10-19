export const slippageBps = 100n;
export const bpsDenominator = 10_000n;

export function minAmountAfterSlippage(
  amount: bigint,
  bps: bigint = slippageBps,
): bigint {
  return (amount * (bpsDenominator - bps)) / bpsDenominator;
}
