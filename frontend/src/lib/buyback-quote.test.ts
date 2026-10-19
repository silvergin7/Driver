import { describe, expect, it } from "vitest";
import { deferredQuoteError, planBuyback } from "./buyback-quote";

describe("planBuyback", () => {
  it("quotes held rewards when no farm is active", () => {
    expect(
      planBuyback({
        hasActiveFarm: false,
        heldRewards: 10n,
        pendingBuyback: 4n,
        pendingRewards: 100n,
        quote: { status: "quoted", amountOut: 1_000n, usdcTax: 1n },
        rewardReserve: 1n,
      }),
    ).toEqual({ status: "ready", spend: 9n, minDvrOut: 990n });
  });

  it("does not spend a pending buyback when the half is zero", () => {
    expect(
      planBuyback({
        hasActiveFarm: false,
        heldRewards: 1n,
        pendingBuyback: 50n,
        pendingRewards: 0n,
        quote: { status: "waiting" },
        rewardReserve: 0n,
      }),
    ).toEqual({ status: "skip", spend: 0n, minDvrOut: 0n });
  });

  it("caps pending rewards at the reward reserve", () => {
    expect(
      planBuyback({
        hasActiveFarm: true,
        heldRewards: 0n,
        pendingBuyback: 0n,
        pendingRewards: 100n,
        quote: { status: "quoted", amountOut: 500n, usdcTax: 1n },
        rewardReserve: 10n,
      }),
    ).toEqual({ status: "ready", spend: 5n, minDvrOut: 495n });
  });

  it("skips the minimum when the tax is above the spend", () => {
    expect(
      planBuyback({
        hasActiveFarm: true,
        heldRewards: 4n,
        pendingBuyback: 0n,
        pendingRewards: 0n,
        quote: { status: "quoted", amountOut: 10n, usdcTax: 3n },
        rewardReserve: 0n,
      }).status,
    ).toBe("skip");
  });

  it("skips the minimum when the quote has no output", () => {
    expect(
      planBuyback({
        hasActiveFarm: true,
        heldRewards: 0n,
        pendingBuyback: 0n,
        pendingRewards: 4n,
        quote: { status: "quoted", amountOut: 0n, usdcTax: 1n },
        rewardReserve: 4n,
      }).status,
    ).toBe("skip");
  });

  it("skips when no farm is active and nothing is held", () => {
    expect(
      planBuyback({
        hasActiveFarm: false,
        heldRewards: 0n,
        pendingBuyback: 0n,
        pendingRewards: 100n,
        quote: { status: "quoted", amountOut: 1_000n, usdcTax: 1n },
        rewardReserve: 100n,
      }),
    ).toEqual({ status: "skip", spend: 0n, minDvrOut: 0n });
  });

  it("blocks the harvest when the quote reverts for another reason", () => {
    expect(
      planBuyback({
        hasActiveFarm: true,
        heldRewards: 4n,
        pendingBuyback: 0n,
        pendingRewards: 0n,
        quote: { status: "block" },
        rewardReserve: 0n,
      }).status,
    ).toBe("blocked");
  });
});

describe("deferredQuoteError", () => {
  it("defers a zero amount and a zero output", () => {
    expect(deferredQuoteError("OfficialPool__ZeroAmount")).toBe(true);
    expect(deferredQuoteError("OfficialPool__ZeroOutput")).toBe(true);
  });

  it("does not defer another error", () => {
    expect(deferredQuoteError("OfficialPool__InsufficientOutput")).toBe(false);
  });
});
