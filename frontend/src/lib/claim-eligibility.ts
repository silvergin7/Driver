export type ClaimEligibility =
  | { status: "allowed" }
  | { status: "cooldown" }
  | { status: "daily-cap" }
  | { status: "faucet-empty" };

export type ClaimWindowInput = {
  blockTimestamp: bigint;
  nextClaimAt: bigint;
  claimsToday: bigint;
  dailyClaimLimit: bigint;
};

export type ClaimEligibilityInput = ClaimWindowInput & {
  faucetBalance: bigint;
  claimAmount: bigint;
};

export function claimWindow(
  input: ClaimWindowInput,
): Exclude<ClaimEligibility, { status: "faucet-empty" }> {
  if (input.claimsToday >= input.dailyClaimLimit) {
    return { status: "daily-cap" };
  }
  if (input.nextClaimAt !== 0n && input.blockTimestamp < input.nextClaimAt) {
    return { status: "cooldown" };
  }
  return { status: "allowed" };
}

export function claimEligibility(
  input: ClaimEligibilityInput,
): ClaimEligibility {
  const window = claimWindow(input);
  if (window.status !== "allowed") {
    return window;
  }
  if (input.faucetBalance < input.claimAmount) {
    return { status: "faucet-empty" };
  }
  return { status: "allowed" };
}
