export type ClaimEligibility =
  | { status: "allowed" }
  | { status: "cooldown" }
  | { status: "daily-cap" }
  | { status: "faucet-empty" };

export type ClaimEligibilityInput = {
  blockTimestamp: bigint;
  nextClaimAt: bigint;
  claimsToday: bigint;
  dailyClaimLimit: bigint;
  faucetBalance: bigint;
  claimAmount: bigint;
};

export function claimEligibility(
  input: ClaimEligibilityInput,
): ClaimEligibility {
  if (input.claimsToday >= input.dailyClaimLimit) {
    return { status: "daily-cap" };
  }
  if (input.nextClaimAt !== 0n && input.blockTimestamp < input.nextClaimAt) {
    return { status: "cooldown" };
  }
  if (input.faucetBalance < input.claimAmount) {
    return { status: "faucet-empty" };
  }
  return { status: "allowed" };
}
