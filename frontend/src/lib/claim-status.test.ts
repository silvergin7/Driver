import { describe, expect, it } from "vitest";
import { claimStatus, type ClaimStatusInput } from "./claim-status";

const idle: ClaimStatusInput = {
  claimed: undefined,
  confirming: false,
  connected: true,
  eligibility: "allowed",
  onAnvil: true,
  readsFailed: false,
  readsReady: true,
  simulating: false,
  writePending: false,
};

describe("claimStatus", () => {
  it("returns ready when a claim is allowed and idle", () => {
    expect(claimStatus(idle)).toBe("Ready to claim.");
  });

  it.each(["daily-cap", "cooldown", "faucet-empty"] as const)(
    "returns nothing for %s while idle",
    (eligibility) => {
      expect(claimStatus({ ...idle, eligibility })).toBeUndefined();
    },
  );

  it("prefers the claimed message over a blocked state", () => {
    expect(
      claimStatus({
        ...idle,
        claimed: "Claimed 10 DVR.",
        eligibility: "daily-cap",
      }),
    ).toBe("Claimed 10 DVR.");
  });

  it("returns the simulating message", () => {
    expect(claimStatus({ ...idle, simulating: true })).toBe(
      "Checking the claim.",
    );
  });

  it("returns the wallet message", () => {
    expect(claimStatus({ ...idle, writePending: true })).toBe(
      "Waiting for the wallet.",
    );
  });

  it("returns the confirming message", () => {
    expect(claimStatus({ ...idle, confirming: true })).toBe(
      "Confirming the claim.",
    );
  });
});
