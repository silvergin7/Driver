export function ringFraction(remaining: bigint, period: bigint): number {
  if (period <= 0n || remaining >= period) {
    return 0;
  }
  if (remaining <= 0n) {
    return 1;
  }
  return 1 - Number(remaining) / Number(period);
}

export function ringPresentation(input: {
  dailyCap: boolean;
  remaining: bigint;
  period: bigint;
}): { fraction: number; grey: boolean } {
  if (input.dailyCap) {
    return { fraction: 0, grey: true };
  }
  return { fraction: ringFraction(input.remaining, input.period), grey: false };
}
