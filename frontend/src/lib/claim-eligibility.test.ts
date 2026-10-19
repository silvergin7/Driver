import { describe, expect, it } from "vitest";
import {
  claimEligibility,
  claimWindow,
  type ClaimEligibilityInput,
} from "./claim-eligibility";

const claimAmount = 10n * 10n ** 18n;

function input(
  overrides: Partial<ClaimEligibilityInput>,
): ClaimEligibilityInput {
  return {
    blockTimestamp: 1n,
    nextClaimAt: 0n,
    claimsToday: 0n,
    dailyClaimLimit: 25n,
    faucetBalance: claimAmount,
    claimAmount,
    ...overrides,
  };
}

describe("claimEligibility", () => {
  it("allows a wallet that has never claimed when the day is open and the faucet can pay", () => {
    expect(claimEligibility(input({})).status).toBe("allowed");
  });

  it("treats nextClaimAt of 0 as never claimed", () => {
    expect(
      claimEligibility(input({ nextClaimAt: 0n, blockTimestamp: 1n })).status,
    ).toBe("allowed");
  });

  it("returns cooldown when the block timestamp is before nextClaimAt", () => {
    expect(
      claimEligibility(input({ nextClaimAt: 100n, blockTimestamp: 99n }))
        .status,
    ).toBe("cooldown");
  });

  it("returns allowed when the block timestamp equals nextClaimAt", () => {
    expect(
      claimEligibility(input({ nextClaimAt: 100n, blockTimestamp: 100n }))
        .status,
    ).toBe("allowed");
  });

  it("returns the daily cap when claimsToday equals the limit, even if the balance is zero and the wallet is in cooldown", () => {
    expect(
      claimEligibility(
        input({
          claimsToday: 25n,
          nextClaimAt: 1_000n,
          blockTimestamp: 1n,
          faucetBalance: 0n,
        }),
      ).status,
    ).toBe("daily-cap");
  });

  it("returns faucet empty only when the cap is open, the cooldown has passed, and the balance is below one claim", () => {
    expect(
      claimEligibility(
        input({
          nextClaimAt: 50n,
          blockTimestamp: 50n,
          faucetBalance: claimAmount - 1n,
        }),
      ).status,
    ).toBe("faucet-empty");
  });

  it("returns allowed when the faucet balance equals one claim", () => {
    expect(
      claimEligibility(input({ faucetBalance: claimAmount })).status,
    ).toBe("allowed");
  });
});

describe("claimWindow", () => {
  it("allows a wallet that has never claimed when the day is open", () => {
    expect(
      claimWindow({
        blockTimestamp: 1n,
        claimsToday: 0n,
        dailyClaimLimit: 25n,
        nextClaimAt: 0n,
      }).status,
    ).toBe("allowed");
  });

  it("returns cooldown before nextClaimAt", () => {
    expect(
      claimWindow({
        blockTimestamp: 99n,
        claimsToday: 0n,
        dailyClaimLimit: 25n,
        nextClaimAt: 100n,
      }).status,
    ).toBe("cooldown");
  });

  it("returns the daily cap ahead of a cooldown", () => {
    expect(
      claimWindow({
        blockTimestamp: 1n,
        claimsToday: 25n,
        dailyClaimLimit: 25n,
        nextClaimAt: 1_000n,
      }).status,
    ).toBe("daily-cap");
  });
});
